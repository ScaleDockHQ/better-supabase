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
    const verify = vi.spyOn(crypto.subtle, "verify");

    const request = new Request("https://app.test/two", {
      headers: { cookie: await sessionCookie(3600, "r-two") },
    });

    const loader = async () => {
      const ctx = await bsb.contextFromSession(await bsb.snapshot(request));

      return ctx.auth.kind === "user" ? ctx.auth.user.id : null;
    };

    expect(await Promise.all([loader(), loader()])).toEqual([USER, USER]);
    expect(verify).toHaveBeenCalledOnce();
    verify.mockRestore();
  });

  it("never refreshes an expired cookie on a prefetch", async () => {
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
    expect(refreshed).not.toHaveBeenCalled();

    await bsb.middleware()(immutable("https://app.test/prefetch", headers));
    expect(refreshed).toHaveBeenCalledOnce();
  });
});
