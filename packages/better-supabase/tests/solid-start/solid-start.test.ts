import { describe, expect, it } from "vitest";

import { ok } from "../../src/core/result.ts";
import {
  createSolidStart,
  type SolidFetchEvent,
} from "../../src/solid-start/index.ts";
import {
  betterSupabase,
  env,
  requestAs,
  signer,
  USER,
} from "../fixtures/test-server.ts";

let current: SolidFetchEvent | undefined;

const bs = createSolidStart(betterSupabase, {
  env,
  auth: { jwks: signer.jwks as never },
  prefetchJwks: false,
  signIn: "/sign-in",
  getRequestEvent: () => current,
});

/** Runs the middleware, then `fn` as a server function of that request. */
async function serve<T>(
  request: Request,
  fn: () => Promise<T>,
): Promise<{
  readonly event: SolidFetchEvent;
  readonly short?: Response;
  readonly out?: T;
}> {
  const event: SolidFetchEvent = {
    request,
    response: { headers: new Headers() },
    locals: {},
  };
  const short = await bs.middleware.onRequest(event);
  if (short) return { event, short };
  current = event;
  try {
    return { event, out: await fn() };
  } finally {
    current = undefined;
    bs.middleware.onBeforeResponse(event);
  }
}

describe("createSolidStart", () => {
  it("fills event.locals, and require returns the caller", async () => {
    const { out } = await serve(await requestAs({ role: "member" }), () =>
      bs.require(),
    );
    expect(out?.session).toMatchObject({ user: { id: USER } });
    const { out: locals } = await serve(await requestAs(), () =>
      Promise.resolve(bs.locals()),
    );
    expect(locals?.bs.auth.kind).toBe("anon");
  });

  it("throws a redirect or Problem Details for refused callers", async () => {
    const anonymous = serve(
      await requestAs(undefined, { url: "https://app.test/notes" }),
      () => bs.require(),
    );
    await expect(anonymous).rejects.toSatisfy(
      (response: Response) =>
        response.status === 303 &&
        response.headers.get("location") ===
          "https://app.test/sign-in?next=%2Fnotes",
    );
    await expect(
      serve(await requestAs({ role: "member" }), () =>
        bs.require({ roles: ["admin"] }),
      ),
    ).rejects.toSatisfy((response: Response) => response.status === 403);
  });

  it("runs actions into ActionResults", async () => {
    const save = bs.action({}, (input) => ok({ input }));
    const form = new FormData();
    form.append("title", "Hello");
    const { out } = await serve(await requestAs({ role: "member" }), () =>
      save(form),
    );
    expect(out).toEqual({
      ok: true,
      data: { input: { title: "Hello" } },
      error: null,
    });
  });

  it("needs the middleware and a request event", () => {
    expect(() => bs.locals()).toThrow(/src\/middleware.ts/);
  });

  it("reads the env from the native event's Cloudflare bindings", async () => {
    const event: SolidFetchEvent = {
      request: await requestAs(),
      response: { headers: new Headers() },
      locals: {},
      nativeEvent: { context: { cloudflare: { env: {} } } },
    };
    expect(await bs.middleware.onRequest(event)).toBeUndefined();
    expect(event.locals).toHaveProperty("db");
  });
});
