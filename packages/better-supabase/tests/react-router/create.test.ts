import { describe, expect, it, vi } from "vitest";

import type { ReactRouterArgs } from "../../src/react-router/index.ts";

import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { createReactRouter } from "../../src/react-router/index.ts";
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

/** A minimal `RouterContextProvider`: a map keyed by context objects. */
function contextProvider(): ReactRouterArgs["context"] {
  const values = new Map<unknown, unknown>();

  return {
    get: (key) => {
      if (!values.has(key)) {
        throw new Error("no value");
      }

      return values.get(key);
    },
    set: (key, value) => {
      values.set(key, value);
    },
  };
}

const bsb = createReactRouter(betterSupabase, {
  env,
  auth: { jwks: signer.jwks },
  prefetchJwks: false,
  createContext: () => ({}),
  signIn: "/sign-in",
});

/** Runs the middleware, then `fn` inside it. */
async function serve(
  request: Request,
  fn: (args: ReactRouterArgs) => Promise<unknown>,
) {
  const args = { request, context: contextProvider() };
  let out: unknown;
  let thrown: unknown;
  await bsb.middleware(args, async () => {
    try {
      out = await fn(args);
    } catch (error) {
      thrown = error;
    }

    return new Response(null);
  });

  if (thrown !== undefined) {
    // oxlint-disable-next-line typescript/only-throw-error -- rethrows the thrown Response the adapter answers with.
    throw thrown;
  }

  return out;
}

describe("createReactRouter", () => {
  it("guards loaders and unwraps their Results", async () => {
    const loader = bsb.loader({}, (_args, ctx) =>
      ok({ id: ctx.session.kind === "user" ? ctx.session.user.id : null }),
    );

    expect(await serve(await requestAs({ role: "member" }), loader)).toEqual({
      id: USER,
    });
  });

  it("throws a redirect or Problem Details response for refusals and errors", async () => {
    const loader = bsb.loader({}, () => 1);

    const redirect = await serve(
      await requestAs(undefined, { url: "https://app.test/notes" }),
      loader,
    ).catch((error: unknown) => error);

    expect(redirect).toBeInstanceOf(Response);
    expect((redirect as Response).status).toBe(303);

    const failing = bsb.loader({}, () => err(dbError("not_found", "Gone")));

    const problem = await serve(
      await requestAs({ role: "member" }),
      failing,
    ).catch((error: unknown) => error);

    expect((problem as Response).status).toBe(404);
  });

  it("runs actions into ActionResults", async () => {
    const action = bsb.action({}, (input) => ok(input));

    const request = await requestAs(
      { role: "member" },
      {
        method: "POST",
        body: JSON.stringify({ title: "Hello" }),
        headers: { "content-type": "application/json" },
      },
    );

    expect(await serve(request, action)).toEqual({
      ok: true,
      data: { title: "Hello" },
      error: null,
    });
  });

  it("locals fails without the middleware", () => {
    expect(() =>
      bsb.locals({
        request: new Request("https://app.test/"),
        context: contextProvider(),
      }),
    ).toThrow(/middleware/);
  });

  it("verifies once for two loaders in one request", async () => {
    const resolutions = countResolutions(betterSupabase);

    const loader = bsb.loader({}, async (_args, locals) => {
      const ctx = await bsb.contextFromSession(locals.snapshot);

      return ctx.auth.kind === "user" ? ctx.auth.user.id : null;
    });

    const users = await serve(await requestAs({ role: "member" }), (args) =>
      Promise.all([loader(args), loader(args)]),
    );

    expect(users).toEqual([USER, USER]);
    expect(resolutions.count()).toBe(1);
    resolutions.stop();
  });

  it("never refreshes an expired cookie on a prefetch", async () => {
    const refresh = vi.fn<typeof fetch>(
      async () => new Response(null, { status: 500 }),
    );

    const prefetching = createReactRouter(betterSupabase, {
      env,
      auth: { jwks: signer.jwks, fetch: refresh },
      prefetchJwks: false,
      createContext: () => ({}),
    });

    const load = async (prefetch: boolean) =>
      prefetching.middleware(
        {
          request: await expiredRequest("https://app.test/notes", prefetch),
          context: contextProvider(),
        },
        async () => new Response(null),
      );

    await load(true);
    expect(refresh).not.toHaveBeenCalled();
    await load(false);
    expect(refresh).toHaveBeenCalledOnce();
  });
});
