import type { PostgresApi } from "@supabase/server/middleware/postgres";

import { defineMiddleware, pipeline, seedContext } from "@supabase/middleware";
import { describe, expect, it, vi } from "vitest";

import type { BetterPostgres, SqlClaims } from "../../../src/postgres/pool.ts";

import {
  readSession,
  sessionCookieName,
  writeSession,
} from "../../../src/auth/session.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { postgresExecutor } from "../../../src/postgres/executor.ts";
import { withBetterSupabase } from "../../../src/server/composite.ts";
import { authModeOf } from "../../../src/server/entries/claims.ts";
import { serverCore } from "../../../src/server/entries/core.ts";
import { PRIMARY_COOKIE } from "../../../src/server/replicas.ts";
import { createServer } from "../../../src/server/server.ts";
import { createTestSigner } from "../../../src/testing/jwt.ts";
import { fakeSql } from "../../fixtures/fake-sql.ts";
import { schema } from "../../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();
const betterSupabase = defineSupabase(schema);
const server = createServer(betterSupabase, {
  env,
  auth: { jwks: signer.jwks as never },
  readUrl: "https://replica.test",
  prefetchJwks: false,
});
const request = (token?: string) =>
  new Request("https://api.test/notes", {
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });

describe("withBetterSupabase", () => {
  it("contributes the caller's context and the withSupabase keys", async () => {
    const token = await signer.sign({ sub: USER });
    let seen: Record<string, unknown> | undefined;
    const fetch = pipeline([withBetterSupabase(server)], (_req, ctx) => {
      seen = {
        keys: Object.keys(ctx).toSorted(),
        authMode: ctx.authMode,
        sub: ctx.jwtClaims?.sub,
        user: ctx.userClaims?.id,
        kind: ctx.bs.auth.kind,
        actor: ctx.db.$context.actor?.id,
        sql: ctx.sql,
        tenant: ctx.tenant,
        support: ctx.support,
        replica: ctx.replica !== undefined,
      };
      return Promise.resolve(Response.json({ ok: true }));
    });
    const response = await fetch(request(token));
    expect(response.status).toBe(200);
    expect(seen).toEqual({
      keys: [
        "authMode",
        "bs",
        "db",
        "jwtClaims",
        "replica",
        "sql",
        "support",
        "tenant",
        "userClaims",
      ],
      authMode: "user",
      sub: USER,
      user: USER,
      kind: "user",
      actor: USER,
      sql: undefined,
      tenant: undefined,
      support: undefined,
      replica: true,
    });
  });

  it("refuses callers the guard rejects with Problem Details", async () => {
    const handler = vi.fn(() => Promise.resolve(new Response("ran")));
    const fetch = pipeline([withBetterSupabase(server)], handler);
    const response = await fetch(request());
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({
      instance: "/notes",
      code: "MISSING_CREDENTIALS",
    });
    expect(handler).not.toHaveBeenCalled();
  });

  it("lets callers through that allow admits", async () => {
    const fetch = pipeline(
      [withBetterSupabase(server, { allow: ["anon"] })],
      (_req, ctx) => Promise.resolve(Response.json({ mode: ctx.authMode })),
    );
    expect(await (await fetch(request())).json()).toEqual({ mode: "none" });
  });

  it("answers an invalid token with 401, never as anon", async () => {
    const fetch = pipeline(
      [withBetterSupabase(server, { allow: ["anon"] })],
      () => Promise.resolve(new Response("ran")),
    );
    expect((await fetch(request("not-a-jwt"))).status).toBe(401);
  });

  it("sets bs-primary-until on the way out after a write", async () => {
    const token = await signer.sign({ sub: USER });
    const fetch = pipeline([withBetterSupabase(server)], (_req, ctx) => {
      ctx.replica?.pin();
      return Promise.resolve(new Response(null, { status: 204 }));
    });
    const response = await fetch(request(token));
    expect(
      response.headers
        .getSetCookie()
        .some((cookie) => cookie.startsWith(`${PRIMARY_COOKIE}=`)),
    ).toBe(true);
  });

  it("hands pending event sends to waitUntil", async () => {
    const { promise, resolve } = Promise.withResolvers<void>();
    const waited: Promise<unknown>[] = [];
    const fetch = pipeline(
      [
        withBetterSupabase(server, {
          allow: ["anon"],
          waitUntil: (pending) => waited.push(pending),
        }),
      ],
      () => {
        betterSupabase.events.track(promise);
        return Promise.resolve(new Response(null));
      },
    );
    await fetch(request());
    resolve();
    expect(waited).toHaveLength(1);
    await Promise.all(waited);
  });

  it("builds a server from the definition and its server options", async () => {
    const token = await signer.sign({ sub: USER });
    const fetch = pipeline(
      [
        withBetterSupabase(betterSupabase, {
          env,
          auth: { jwks: signer.jwks as never },
          prefetchJwks: false,
        }),
      ],
      (_req, ctx) => Promise.resolve(Response.json({ id: ctx.userClaims?.id })),
    );
    expect(await (await fetch(request(token))).json()).toEqual({ id: USER });
  });

  it("runs ctx.sql over createServer's postgres as the caller", async () => {
    const fake = fakeSql([[/customers/, [{ row: { id: "c1" } }]]]);
    const claims: SqlClaims[] = [];
    // SAFETY: the server only calls executorFor; the executor only calls queryRaw.
    const postgres = {
      executorFor: (value: SqlClaims) => {
        claims.push(value);
        return postgresExecutor(fake.sql);
      },
    } as unknown as BetterPostgres;
    const withSql = createServer(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
      postgres,
      prefetchJwks: false,
    });
    const token = await signer.sign({ sub: USER });
    const fetch = pipeline([withBetterSupabase(withSql)], async (_req, ctx) =>
      Response.json(
        await ctx.sql?.customers.findMany({ select: ["id"] }).orThrow(),
      ),
    );
    expect(await (await fetch(request(token))).json()).toEqual([{ id: "c1" }]);
    expect(fake.texts()[0]).toContain("customers");
    expect(claims[0]).toMatchObject({ sub: USER, role: "authenticated" });
  });

  it("leaves an upstream ctx.postgres alone and ctx.sql unset", async () => {
    const fake = fakeSql();
    const withPostgres = defineMiddleware<
      "postgres",
      undefined,
      Record<never, never>,
      PostgresApi
    >({
      key: "postgres",
      run: () => () =>
        // SAFETY: the handler only compares the reference.
        Promise.resolve({ postgres: fake.sql as unknown as PostgresApi }),
    });
    const fetch = pipeline(
      [withPostgres(), withBetterSupabase(server, { allow: ["anon"] })],
      (_req, ctx) =>
        Promise.resolve(
          Response.json({
            sql: ctx.sql === undefined,
            postgres: ctx.postgres === (fake.sql as unknown),
          }),
        ),
    );
    expect(await (await fetch(request())).json()).toEqual({
      sql: true,
      postgres: true,
    });
  });

  it("keeps an upstream key the composite uses internally", async () => {
    const withUpstreamAuth = defineMiddleware<
      "auth",
      undefined,
      Record<never, never>,
      string
    >({
      key: "auth",
      run: () => () => Promise.resolve({ auth: "upstream" }),
    });
    const token = await signer.sign({ sub: USER });
    const fetch = pipeline(
      [withUpstreamAuth(), withBetterSupabase(server)],
      (_req, ctx) => Promise.resolve(Response.json({ auth: ctx.auth })),
    );
    expect(await (await fetch(request(token))).json()).toEqual({
      auth: "upstream",
    });
  });
});

describe("server.context", () => {
  it("runs the entries once per call with the call's options", async () => {
    const token = await signer.sign({ sub: USER });
    const ctx = await server.context(request(token), { tenant: "acme" });
    expect(ctx.auth.kind).toBe("user");
    expect(ctx.db.$context.tenant).toBe("acme");
    const anon = await server.context(request());
    expect(anon.auth.kind).toBe("anon");
    expect(anon.db.$context.tenant).toBeUndefined();
  });

  it("refuses a server that createServer did not build", () => {
    expect(() =>
      serverCore({
        events: betterSupabase.events,
        context: () => Promise.reject(new Error("unused")),
      }),
    ).toThrow("was not built by createServer()");
  });
});

describe("authModeOf", () => {
  it("names each caller the way withSupabase does", () => {
    expect(authModeOf({ kind: "service", keyName: "default" })).toBe("secret");
    expect(authModeOf({ kind: "anon", reason: "none" })).toBe("none");
  });
});

it("seeds like a host would", async () => {
  const fetch = pipeline(
    [withBetterSupabase(server, { allow: ["anon"] })],
    (_req, ctx) => Promise.resolve(Response.json({ mode: ctx.authMode })),
  );
  const response = await fetch(request(), seedContext({}));
  expect(response.status).toBe(200);
});

describe("session cookies", () => {
  const NAME = sessionCookieName(PROJECT_URL);
  const expired = async () => {
    const token = await signer.sign({
      sub: USER,
      exp: Math.floor(Date.now() / 1000) - 60,
    });
    const writes = writeSession([], NAME, {
      access_token: token,
      refresh_token: "r-old",
      expires_at: Math.floor(Date.now() / 1000) - 60,
      token_type: "bearer",
      user: { id: USER },
    });
    return writes.map((write) => `${write.name}=${write.value}`).join("; ");
  };

  it("writes a refreshed session in the configured encoding", async () => {
    const fresh = await signer.sign({ sub: USER });
    const refreshing = createServer(betterSupabase, {
      env,
      auth: {
        jwks: signer.jwks as never,
        fetch: vi.fn<typeof globalThis.fetch>(async () =>
          Response.json({
            access_token: fresh,
            refresh_token: "r-next",
            expires_in: 3600,
            token_type: "bearer",
            user: { id: USER },
          }),
        ),
      },
      prefetchJwks: false,
    });
    const fetch = pipeline(
      [
        withBetterSupabase(refreshing, {
          refresh: true,
          encode: "tokens-only",
        }),
      ],
      (_req, ctx) => Promise.resolve(Response.json({ kind: ctx.bs.auth.kind })),
    );
    const response = await fetch(
      new Request("https://app.test/", {
        headers: { cookie: await expired() },
      }),
    );
    expect(await response.json()).toEqual({ kind: "user" });
    const written = readSession(
      response.headers.getSetCookie().map((cookie) => {
        const [pair = ""] = cookie.split(";");
        const at = pair.indexOf("=");
        return { name: pair.slice(0, at), value: pair.slice(at + 1) };
      }),
      NAME,
    );
    expect(written?.access_token).toBe(fresh);
    expect(written?.user).toBeUndefined();
  });

  it("expires the session cookie at old scopes", async () => {
    const fetch = pipeline(
      [
        withBetterSupabase(server, {
          allow: ["anon", "user"],
          cookieScopes: [{ domain: "old.test" }, { path: "/app" }],
        }),
      ],
      () => Promise.resolve(new Response("ok")),
    );
    const response = await fetch(
      new Request("https://app.test/", {
        headers: { cookie: `${NAME}=x` },
      }),
    );
    const cleared = response.headers
      .getSetCookie()
      .filter((cookie) => cookie.startsWith(`${NAME}=`));
    expect(cleared).toHaveLength(2);
    expect(cleared.every((cookie) => cookie.includes("Max-Age=0"))).toBe(true);
    expect(cleared.some((cookie) => cookie.includes("Domain=old.test"))).toBe(
      true,
    );
    expect(response.headers.get("cache-control")).toContain("no-store");

    const none = await fetch(new Request("https://app.test/"));
    expect(none.headers.getSetCookie()).toEqual([]);
  });
});
