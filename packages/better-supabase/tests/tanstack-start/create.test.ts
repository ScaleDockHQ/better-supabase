import { describe, expect, it, vi } from "vitest";

import { ok } from "../../src/core/result.ts";
import { createTanStackStart } from "../../src/tanstack-start/index.ts";
import {
  countResolutions,
  expiredRequest,
} from "../fixtures/instant-sessions.ts";
import {
  betterSupabase,
  env,
  requestAs,
  signer,
  USER,
} from "../fixtures/test-server.ts";

const bsb = createTanStackStart(betterSupabase, {
  env,
  auth: { jwks: signer.jwks },
  prefetchJwks: false,
});

type Context = Parameters<typeof bsb.require>[0];

/** Runs the request middleware and hands its context to `fn`. */
async function serve(
  request: Request,
  fn: (context: Context) => Promise<unknown>,
) {
  let out: unknown;
  let thrown: unknown;
  await bsb.middleware({
    request,
    next: async ({ context }) => {
      try {
        out = await fn(context);
      } catch (error) {
        thrown = error;
      }

      return new Response(null);
    },
  });

  if (thrown !== undefined) {
    // oxlint-disable-next-line typescript/only-throw-error -- rethrows the thrown Response the adapter answers with.
    throw thrown;
  }

  return out;
}

describe("createTanStackStart", () => {
  it("puts the caller on context, and require returns it", async () => {
    const caller = await serve(await requestAs({ role: "member" }), (context) =>
      bsb.require(context),
    );

    expect(caller).toMatchObject({ session: { user: { id: USER } } });
  });

  it("throws a Problem Details response for refused callers", async () => {
    const refused = await serve(await requestAs(), (context) =>
      bsb.require(context),
    ).catch((error: unknown) => error);

    expect((refused as Response).status).toBe(401);
  });

  it("runs server function handlers into ActionResults", async () => {
    const handler = bsb.action({ requireTenant: true }, () => ok(1));

    const result = await serve(await requestAs({ role: "member" }), (context) =>
      handler({ data: {}, context }),
    );

    expect(result).toMatchObject({ ok: false, error: { code: "NO_TENANT" } });
  });

  it("require fails without the middleware", async () => {
    await expect(bsb.require({} as never)).rejects.toThrow(/middleware/);
  });

  it("verifies once for two loaders in one request", async () => {
    const resolutions = countResolutions(betterSupabase);

    const loader = async (context: Context) => {
      const { snapshot } = await bsb.require(context);
      const ctx = await bsb.contextFromSession(snapshot);

      return ctx.auth.kind === "user" ? ctx.auth.user.id : null;
    };

    const users = await serve(await requestAs({ role: "member" }), (context) =>
      Promise.all([loader(context), loader(context)]),
    );

    expect(users).toEqual([USER, USER]);
    expect(resolutions.count()).toBe(1);
    resolutions.stop();
  });

  it("never refreshes an expired cookie on a prefetch", async () => {
    const refresh = vi.fn<typeof fetch>(
      async () => new Response(null, { status: 500 }),
    );

    const prefetching = createTanStackStart(betterSupabase, {
      env,
      auth: { jwks: signer.jwks, fetch: refresh },
      prefetchJwks: false,
    });

    const load = async (prefetch: boolean) =>
      prefetching.middleware({
        request: await expiredRequest("https://app.test/notes", prefetch),
        next: async () => new Response(null),
      });

    await load(true);
    expect(refresh).not.toHaveBeenCalled();
    await load(false);
    expect(refresh).toHaveBeenCalledOnce();
  });
});
