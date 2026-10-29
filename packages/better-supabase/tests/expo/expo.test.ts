import { StatusError } from "expo-server";
import { ImmutableRequest } from "expo-server/private";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { writeSession } from "../../src/auth/session.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { dbError, DbException } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { createExpo } from "../../src/expo/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { countResolutions } from "../fixtures/instant-sessions.ts";

const written = vi.hoisted(() => ({ headers: new Headers() }));

vi.mock("expo-server", async (importOriginal) => ({
  ...(await importOriginal<Record<string, unknown>>()),
  setResponseHeaders: (
    update: Headers | Record<string, string> | ((headers: Headers) => void),
  ) => {
    if (typeof update === "function") {
      update(written.headers);
    } else {
      for (const [name, value] of new Headers(update)) {
        written.headers.append(name, value);
      }
    }
  },
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();
const COOKIE = "sb-abcdefghijklmnopqrst-auth-token";

async function sessionCookie(
  expiresIn: number,
  refreshToken: string,
): Promise<string> {
  const token = await signer.sign({ sub: USER, expiresIn });

  return writeSession([], COOKIE, {
    access_token: token,
    refresh_token: refreshToken,
    expires_at: Math.floor(Date.now() / 1000) + expiresIn,
    token_type: "bearer",
    user: { id: USER },
  })
    .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
    .join("; ");
}

const immutable = (url: string, headers: Record<string, string> = {}) =>
  new ImmutableRequest(new Request(url, { headers }));

describe("createExpo", () => {
  const refreshed = vi.fn(async () =>
    Response.json({
      access_token: await signer.sign({ sub: USER }),
      refresh_token: "r-next",
      expires_in: 3600,
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      token_type: "bearer",
      user: { id: USER },
    }),
  );

  const betterSupabase = defineSupabase(schema);

  const bsb = createExpo(betterSupabase, {
    env,
    auth: { jwks: signer.jwks, fetch: refreshed },
  });

  beforeEach(() => {
    written.headers = new Headers();
    refreshed.mockClear();
  });

  it("verifies a bearer token before the cookie and writes nothing", async () => {
    const token = await signer.sign({ sub: USER });

    const ctx = await bsb.request(
      immutable("https://app.test/", {
        authorization: `Bearer ${token}`,
        cookie: await sessionCookie(3600, "r-unused"),
      }),
    );

    expect(ctx.auth).toMatchObject({ kind: "user", source: "bearer" });
    expect([...written.headers]).toEqual([]);
    expect(refreshed).not.toHaveBeenCalled();
  });

  it("refreshes an expired cookie session and sets the cookies on the response", async () => {
    const cookie = await sessionCookie(5, "r-loader");

    const loader = bsb.loader((ctx, params) => ({
      user: ctx.auth.kind === "user" ? ctx.auth.user.id : null,
      params,
    }));

    expect(
      await loader(immutable("https://app.test/posts/1", { cookie }), {
        id: "1",
      }),
    ).toEqual({ user: USER, params: { id: "1" } });
    expect(refreshed).toHaveBeenCalledOnce();
    expect(written.headers.getSetCookie().join("\n")).toContain(COOKIE);
    expect(written.headers.get("cache-control")).toContain("no-store");

    const middleware = bsb.middleware();
    const before = written.headers.getSetCookie().length;
    expect(
      await middleware(immutable("https://app.test/", { cookie })),
    ).toBeUndefined();
    expect(refreshed).toHaveBeenCalledOnce();
    expect(written.headers.getSetCookie()).toHaveLength(before);
  });

  it("hands the middleware's refreshed session to the same request's loader", async () => {
    const cookie = await sessionCookie(5, "r-handoff");
    const url = "https://app.test/handoff";

    expect(await bsb.middleware()(immutable(url, { cookie }))).toBeUndefined();
    expect(refreshed).toHaveBeenCalledOnce();

    const cookies = written.headers.getSetCookie().length;
    const ctx = await bsb.request(immutable(url, { cookie }));

    expect(ctx.auth).toMatchObject({ kind: "user", source: "cookie" });
    expect(refreshed).toHaveBeenCalledOnce();
    expect(written.headers.getSetCookie()).toHaveLength(cookies);
  });

  it("hands the session over to a loader with refresh off", async () => {
    const cookie = await sessionCookie(-60, "r-handoff-off");
    const url = "https://app.test/handoff-off";

    await bsb.middleware()(immutable(url, { cookie }));

    const loader = bsb.loader((ctx) => ctx.auth.kind, { refresh: false });

    expect(await loader(immutable(url, { cookie }), {})).toBe("user");
    expect(refreshed).toHaveBeenCalledOnce();
  });

  it("refreshes once in a loader when no middleware ran", async () => {
    const cookie = await sessionCookie(5, "r-no-middleware");
    const loader = bsb.loader((ctx) => ctx.auth.kind);

    expect(
      await loader(immutable("https://app.test/no-middleware", { cookie }), {}),
    ).toBe("user");
    expect(refreshed).toHaveBeenCalledOnce();
  });

  it("throws a StatusError for a refused caller and in static rendering", async () => {
    const loader = bsb.loader(() => "secret", { allow: ["user"] });

    const refused = await loader(immutable("https://app.test/"), {}).catch(
      (cause: unknown) => cause,
    );

    expect(refused).toBeInstanceOf(StatusError);
    expect(refused).toMatchObject({ status: 401 });
    await expect(loader(undefined, {})).rejects.toThrow(
      /static rendering has none.*createStaticLoader from "expo-server"/,
    );
  });

  it("answers a DbException from a loader with its status", async () => {
    const missing = bsb.loader(() => {
      throw new DbException(dbError("not_found", "No customer"));
    });

    const refused = await missing(immutable("https://app.test/"), {}).catch(
      (cause: unknown) => cause,
    );

    expect(refused).toBeInstanceOf(StatusError);
    expect(refused).toMatchObject({ status: 404 });

    const failing = bsb.loader(() => {
      throw new TypeError("boom");
    });

    await expect(failing(immutable("https://app.test/"), {})).rejects.toThrow(
      TypeError,
    );
  });

  it("redirects refused callers from middleware", async () => {
    const middleware = bsb.middleware({ redirectTo: "/sign-in" });

    const response = await middleware(
      immutable("https://app.test/account?tab=1"),
    );

    expect(response).toBeInstanceOf(Response);
    expect(response!.status).toBe(303);
    expect(response!.headers.get("location")).toBe(
      "https://app.test/sign-in?next=%2Faccount%3Ftab%3D1",
    );
    expect(
      await middleware(immutable("https://app.test/sign-in")),
    ).toBeUndefined();
    const token = await signer.sign({ sub: USER });
    expect(
      await middleware(
        immutable("https://app.test/account", {
          authorization: `Bearer ${token}`,
        }),
      ),
    ).toBeUndefined();
  });

  it("lets callers through to paths under redirectTo and publicPaths", async () => {
    const middleware = bsb.middleware({
      redirectTo: "/sign-in",
      publicPaths: ["/", "/legal"],
    });

    for (const path of ["/sign-in/callback", "/", "/legal", "/legal/terms"]) {
      expect(
        await middleware(immutable(`https://app.test${path}`)),
      ).toBeUndefined();
    }

    for (const path of ["/sign-inx", "/legalese", "/account"]) {
      expect(
        (await middleware(immutable(`https://app.test${path}`)))?.status,
      ).toBe(303);
    }
  });

  it("answers API routes with JSON and Problem Details", async () => {
    const token = await signer.sign({ sub: USER });

    const handler = bsb.handler((_request, ctx, params) =>
      params["fail"]
        ? err(dbError("not_found", "No such row"))
        : ok({ user: ctx.auth.kind === "user" ? ctx.auth.user.id : null }),
    );

    const request = new Request("https://app.test/api/me", {
      headers: { authorization: `Bearer ${token}` },
    });

    expect(await (await handler(request)).json()).toEqual({ user: USER });
    expect((await handler(request, { fail: "1" })).status).toBe(404);
    expect((await handler(new Request("https://app.test/api/me"))).status).toBe(
      401,
    );

    const throwing = bsb.handler(() => {
      throw new Error("boom");
    });

    const failed = await throwing(request);
    expect(failed.status).toBe(500);
    expect(await failed.text()).not.toContain("boom");
  });

  it("verifies once for two loaders in one request", async () => {
    const resolutions = countResolutions(betterSupabase);

    const request = new Request("https://app.test/two", {
      headers: { cookie: await sessionCookie(3600, "r-two") },
    });

    const loader = async () => {
      const ctx = await bsb.contextFromSession(await bsb.snapshot(request));

      return ctx.auth.kind === "user" ? ctx.auth.user.id : null;
    };

    expect(await Promise.all([loader(), loader()])).toEqual([USER, USER]);
    expect(resolutions.count()).toBe(1);
    resolutions.stop();
  });

  it("refreshes an expired cookie on a prefetch, once for the token", async () => {
    const cookie = await sessionCookie(-60, "r-prefetch");

    const headers = {
      cookie,
      "sec-fetch-dest": "document",
      "sec-fetch-mode": "navigate",
    };

    await bsb.middleware()(
      immutable("https://app.test/prefetch", {
        ...headers,
        "sec-purpose": "prefetch",
      }),
    );
    expect(refreshed).toHaveBeenCalledOnce();

    await bsb.middleware()(immutable("https://app.test/prefetch", headers));
    expect(refreshed).toHaveBeenCalledOnce();
  });
});

describe("createExpo bootstrap, getAccess and cached", () => {
  const seed = vi.fn<(userId: string, version: number) => void>();

  const bsb = createExpo(defineSupabase(schema), {
    env,
    auth: { jwks: signer.jwks },
    versions: {
      get: () => undefined,
      set: () => undefined,
      evict: () => undefined,
      seed,
    } as never,
    tenant: (request) =>
      new URL(request.url).searchParams.get("t") ?? undefined,
  });

  let rpcCalls = 0;

  beforeEach(() => {
    rpcCalls = 0;
    seed.mockReset();
    vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
      if (
        String(input instanceof Request ? input.url : input).includes("/rpc/")
      ) {
        rpcCalls += 1;
      }

      return Response.json({
        session_active: true,
        authz_version: 9,
        token_authz_version: 9,
        tenant: "acme",
        data: { ok: true },
      });
    });
  });

  const bearer = async (): Promise<Record<string, string>> => ({
    authorization: `Bearer ${await signer.sign({ sub: USER, session_id: "s-1", authz_ver: 9 })}`,
  });

  it("shares one call among the loaders of a navigation", async () => {
    const headers = await bearer();

    // Expo wraps the request in a new ImmutableRequest for each loader.
    const [layout, page] = await Promise.all([
      bsb.bootstrap(immutable("https://app.test/team", headers), {
        rpc: "home",
      }),
      bsb.bootstrap(immutable("https://app.test/team", headers), {
        rpc: "home",
      }),
    ]);

    expect(layout).toMatchObject({ authzVersion: 9, data: { ok: true } });
    expect(page).toEqual(layout);
    expect(rpcCalls).toBe(1);
    expect(seed).toHaveBeenCalledWith(USER, 9);

    await bsb.bootstrap(immutable("https://app.test/team", headers), {
      rpc: "home",
      args: { page: 2 },
    });
    expect(rpcCalls).toBe(2);
  });

  it("reads access from a request, with the tenant resolver", async () => {
    const access = await bsb.getAccess(
      immutable("https://app.test/team?t=acme", await bearer()),
    );

    expect(access).toMatchObject({ tenant: "acme", authzVersion: 9 });
    expect((await bsb.getAccess(null)).session.kind).toBe("none");
  });

  it("returns the context and its cache tags", async () => {
    const request = immutable("https://app.test/team", await bearer());

    const cached = await bsb.cached(request, {
      tables: ["tasks"],
      tenant: "acme",
      tags: ["app:team"],
    });

    expect(cached.tenant).toBe("acme");
    expect(cached.session.kind).toBe("user");
    expect(cached.tags).toEqual([
      `bsb:session:${USER}`,
      "bsb:session-id:s-1",
      "bsb:tasks@acme",
      "bsb:tasks@*",
      "app:team",
    ]);
    expect((await bsb.cached(request, { tenant: "acme" })).context).toBe(
      cached.context,
    );
  });
});
