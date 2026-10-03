import * as v from "valibot";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type { AuthEvent, RefreshEvent } from "../../src/core/events.ts";
import type { BetterPostgres, SqlClaims } from "../../src/postgres/pool.ts";

import { writeSession } from "../../src/auth/session.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { createServer } from "../../src/server/server.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const signer = await createTestSigner();

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("createServer headers", () => {
  it("stamps per-request headers on the caller’s PostgREST requests", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(() =>
      Promise.resolve(Response.json([])),
    );
    vi.stubGlobal("fetch", fetch);
    const server = createServer(defineSupabase(schema), {
      env,
      auth: { jwks: signer.jwks as never },
      headers: (request) => ({
        "x-channel": "api",
        "x-request-id": request.headers.get("x-request-id") ?? "",
      }),
    });
    const token = await signer.sign({
      sub: "11111111-1111-4111-8111-111111111111",
    });

    for (const headers of [
      { "x-request-id": "r1" },
      { "x-request-id": "r2", authorization: `Bearer ${token}` },
    ]) {
      const ctx = await server.context(
        new Request("https://api.test/", { headers }),
      );
      await ctx.db.customers.findMany({ select: ["id"] }).orThrow();
    }

    const sent = fetch.mock.calls.map(([, init]) => new Headers(init?.headers));
    expect(
      sent.map((headers) => [
        headers.get("x-channel"),
        headers.get("x-request-id"),
      ]),
    ).toEqual([
      ["api", "r1"],
      ["api", "r2"],
    ]);
    expect(sent[1]!.get("authorization")).toBe(`Bearer ${token}`);
  });
});

describe("createServer claims", () => {
  it("validates claims with the schema from betterSupabase.claims()", async () => {
    const betterSupabase = defineSupabase(schema).claims(
      v.object({ tenant_id: v.pipe(v.string(), v.minLength(1)) }),
    );
    const server = createServer(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
    });
    const request = async (claims: Record<string, unknown>) =>
      new Request("https://api.test/", {
        headers: {
          authorization: `Bearer ${await signer.sign({
            sub: "11111111-1111-4111-8111-111111111111",
            ...claims,
          })}`,
        },
      });

    const ok = await server.context(await request({ tenant_id: "t1" }));
    expect(ok.auth.kind === "user" && ok.auth.claims.tenant_id).toBe("t1");

    const bad = await server.context(await request({}));
    expect(bad.auth).toMatchObject({ kind: "invalid", reason: "claims" });
  });

  it("keeps PermDock claims a loose schema does not list", async () => {
    const betterSupabase = defineSupabase(schema).claims(
      v.looseObject({
        tenant_id: v.optional(v.pipe(v.string(), v.uuid())),
        memberships: v.optional(
          v.array(
            v.looseObject({
              scope: v.string(),
              id: v.string(),
              roles: v.array(v.string()),
            }),
          ),
          [],
        ),
      }),
    );
    const server = createServer(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
    });
    const org = "22222222-2222-4222-8222-222222222222";
    const permdock = {
      tenant_id: org,
      user_role: "member",
      roles: ["support"],
      memberships: [
        {
          scope: "project",
          id: "p1",
          within: { organization: org },
          roles: ["editor"],
          expiresAt: 1_900_000_000,
        },
      ],
      attrs: { department: "sales" },
      authz_ver: 7,
      memberships_truncated: true,
    };
    const token = await signer.sign({
      sub: "11111111-1111-4111-8111-111111111111",
      ...permdock,
    });
    const ctx = await server.context(
      new Request("https://api.test/", {
        headers: { authorization: `Bearer ${token}` },
      }),
    );
    expect(ctx.auth.kind).toBe("user");
    if (ctx.auth.kind !== "user") return;
    expect(ctx.auth.claims).toMatchObject(permdock);
  });
});

describe("createServer userMetadata", () => {
  it("parses the profile with betterSupabase.userMetadata() and warns through the betterSupabase logger", async () => {
    const logger = {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };
    const betterSupabase = defineSupabase(schema, { logger }).userMetadata(
      v.object({ display_name: v.string() }),
    );
    const server = createServer(betterSupabase, {
      env,
      auth: { jwks: signer.jwks as never },
    });
    const request = async (metadata: Record<string, unknown>) =>
      new Request("https://api.test/", {
        headers: {
          authorization: `Bearer ${await signer.sign({
            sub: "11111111-1111-4111-8111-111111111111",
            user_metadata: metadata,
          })}`,
        },
      });

    const ok = await server.context(await request({ display_name: "Ada" }));
    expect(ok.auth).toMatchObject({
      kind: "user",
      profile: { display_name: "Ada" },
    });

    const bad = await server.context(await request({ display_name: 1 }));
    expect(bad.auth.kind).toBe("user");
    expect(bad.auth).not.toHaveProperty("profile");
    expect(logger.warn).toHaveBeenCalledOnce();
  });
});

const USER = "11111111-1111-4111-8111-111111111111";
const secretEnv = { ...env, secretKey: "sb_secret_test" };

function stubFetch() {
  const fetch = vi.fn<typeof globalThis.fetch>(() =>
    Promise.resolve(Response.json([])),
  );
  vi.stubGlobal("fetch", fetch);
  const sent = (index: number) => {
    const [input, init] = fetch.mock.calls[index]!;
    return {
      url: String(input),
      headers: new Headers(init?.headers),
    };
  };
  return { fetch, sent };
}

function fakePostgres() {
  const fake = fakeSql();
  const claims: SqlClaims[] = [];
  // SAFETY: the server only calls asUser; the executor only calls queryRaw.
  const postgres = {
    admin: fake.sql,
    anon: fake.sql,
    asUser: (value: SqlClaims) => {
      claims.push(value);
      return fake.sql;
    },
  } as unknown as BetterPostgres;
  return { postgres, claims, fake };
}

const service: AuthState = { kind: "service", keyName: "default" };
const anon: AuthState = { kind: "anon", reason: "none" };
const user = (token: string): AuthState => ({
  kind: "user",
  token,
  claims: { sub: USER, role: "authenticated" },
  user: { id: USER, role: "authenticated" },
  source: "bearer",
  expiresAt: null,
});

describe("createServer clients", () => {
  it("shares the service and anon clients for the primary only", async () => {
    const { sent } = stubFetch();
    const server = createServer(defineSupabase(schema), { env: secretEnv });
    expect(server.supabaseFor(service)).toBe(server.supabaseFor(service));
    expect(server.supabaseFor(anon)).toBe(server.supabaseFor(anon));
    expect(
      server.supabaseFor({
        kind: "invalid",
        reason: "token",
        error: { kind: "unauthorized", message: "x", status: 401 } as never,
      }),
    ).toBe(server.supabaseFor(anon));
    expect(server.supabaseFor(anon)).not.toBe(server.supabaseFor(service));

    const tagged = server.supabaseFor(service, { "x-job": "nightly" });
    expect(tagged).not.toBe(server.supabaseFor(service));
    await tagged.from("customers").select("id");
    expect(sent(0).headers.get("x-job")).toBe("nightly");
    expect(sent(0).headers.get("apikey")).toBe("sb_secret_test");

    const anonTagged = server.supabaseFor(anon, { "x-job": "public" });
    expect(anonTagged).not.toBe(server.supabaseFor(anon));
    await anonTagged.from("customers").select("id");
    expect(sent(1).headers.get("x-job")).toBe("public");
    expect(sent(1).headers.get("apikey")).toBe("sb_publishable_test");
  });

  it("sends user requests with the user's token and the given headers", async () => {
    const { sent } = stubFetch();
    const server = createServer(defineSupabase(schema), { env });
    await server
      .supabaseFor(user("user-token"), { "x-request-id": "r9" })
      .from("customers")
      .select("id");
    expect(sent(0).headers.get("authorization")).toBe("Bearer user-token");
    expect(sent(0).headers.get("x-request-id")).toBe("r9");
  });

  it("needs a secret key for service clients and admin()", () => {
    const server = createServer(defineSupabase(schema), { env });
    expect(() => server.admin()).toThrow(
      "admin() needs SUPABASE_SECRET_KEY; it is not set",
    );
    expect(() => server.supabaseFor(service, { "x-a": "1" })).toThrow(
      /SUPABASE_SECRET_KEY/,
    );
  });

  it("runs admin() as the service role over the secret key", async () => {
    const { sent } = stubFetch();
    const server = createServer(defineSupabase(schema), { env: secretEnv });
    const db = server.admin({ claims: { role: "service_role", job: "sync" } });
    expect(db.$context.actor).toEqual({
      id: "service",
      kind: "service",
      role: "service_role",
    });
    expect(db.$context.claims).toEqual({ role: "service_role", job: "sync" });
    await db.customers.findMany({ select: ["id"] }).orThrow();
    expect(sent(0).url).toContain(`${PROJECT_URL}/rest/v1/customers`);
    expect(sent(0).headers.get("apikey")).toBe("sb_secret_test");
  });

  it("binds dbFor to the caller and merges extra context", () => {
    const server = createServer(defineSupabase(schema), { env: secretEnv });
    expect(server.dbFor(service).$context.actor).toEqual({
      id: "service:default",
      kind: "service",
      role: "service_role",
    });
    expect(
      server.dbFor(anon, { claims: { role: "anon", locale: "nl" } }).$context
        .claims,
    ).toEqual({ role: "anon", locale: "nl" });
  });
});

describe("createServer contextFor", () => {
  it("builds a request-free context with lazy clients and no cookies", () => {
    const server = createServer(defineSupabase(schema), {
      env,
      readUrl: false,
    });
    const ctx = server.contextFor(anon);
    expect(ctx.supabase).toBe(ctx.supabase);
    expect(ctx.db).toBe(ctx.db);
    expect(ctx.replica).toBeUndefined();
    expect(ctx.sql).toBeUndefined();
    expect(ctx.resolution.cookies).toEqual([]);
    const response = new Response("ok");
    expect(ctx.resolution.apply(response)).toBe(response);
    expect(ctx.stats()).toMatchObject({ calls: 0 });
  });

  it("opens ctx.sql as the user or anon, never for service callers", async () => {
    const { postgres, claims, fake } = fakePostgres();
    const server = createServer(defineSupabase(schema), { env, postgres });
    const signed = server.contextFor(user("t"));
    expect(signed.sql).toBe(signed.sql);
    await signed.sql!.customers.findMany({ select: ["id"] }).orThrow();
    expect(fake.texts()[0]).toContain("customers");
    expect(signed.stats()).toMatchObject({ calls: 1 });
    expect(server.contextFor(anon).sql).toBeDefined();
    expect(server.contextFor(service).sql).toBeUndefined();
    expect(claims).toEqual([
      { sub: USER, role: "authenticated" },
      { role: "anon" },
    ]);
  });
});

describe("createServer actingAs", () => {
  it("needs postgres", () => {
    const server = createServer(defineSupabase(schema), { env });
    expect(() => server.actingAs(USER)).toThrow(
      "Direct Postgres access needs createServer(betterSupabase, { postgres: createPostgres() })",
    );
  });

  it("runs as the user, with the impersonator in act", () => {
    const { postgres, claims } = fakePostgres();
    const server = createServer(defineSupabase(schema), { env, postgres });
    const plain = server.actingAs(USER, { tenant_id: "t1" });
    expect(plain.$context.actor).toEqual({
      id: USER,
      kind: "user",
      role: "authenticated",
    });
    const impersonated = server.actingAs(
      USER,
      { role: "anon" },
      { actor: "admin-1", reason: "support ticket" },
    );
    expect(impersonated.$context.actor).toEqual({
      id: USER,
      kind: "user",
      role: "anon",
      impersonator: "admin-1",
    });
    expect(claims).toEqual([
      { role: "authenticated", tenant_id: "t1", sub: USER },
      {
        role: "anon",
        sub: USER,
        act: { sub: "admin-1", reason: "support ticket" },
      },
    ]);
  });
});

describe("createServer events", () => {
  it("emits an auth event per resolution with its source", async () => {
    const betterSupabase = defineSupabase(schema);
    const events: AuthEvent[] = [];
    betterSupabase.on("auth", (event) => events.push(event));
    const server = createServer(betterSupabase, {
      env: secretEnv,
      auth: { jwks: signer.jwks as never, secret: true },
    });
    const token = await signer.sign({ sub: USER });
    const cookie = writeSession([], "sb-abcdefghijklmnopqrst-auth-token", {
      access_token: token,
      refresh_token: "r",
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      token_type: "bearer",
      user: { id: USER },
    })
      .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
      .join("; ");
    for (const headers of [
      { authorization: `Bearer ${token}` },
      { cookie },
      { apikey: "sb_secret_test" },
      {},
      { authorization: "Bearer junk" },
    ]) {
      await server.resolve(new Request("https://api.test/", { headers }));
    }
    expect(events).toEqual([
      { source: "bearer", ok: true, userId: USER },
      { source: "cookie", ok: true, userId: USER },
      { source: "bearer", ok: true },
      { source: "none", ok: true },
      { source: "none", ok: false },
    ]);
  });

  it("reports refreshes to the auth option and the betterSupabase event bus", async () => {
    const betterSupabase = defineSupabase(schema);
    const events: RefreshEvent[] = [];
    betterSupabase.on("refresh", (event) => events.push(event));
    const onRefresh = vi.fn();
    const server = createServer(betterSupabase, {
      env,
      auth: {
        jwks: signer.jwks as never,
        onRefresh,
        fetch: async () =>
          Response.json({ msg: "Invalid Refresh Token" }, { status: 400 }),
      },
    });
    const stale = await signer.sign({ sub: USER, expiresIn: 10 });
    const cookie = writeSession([], "sb-abcdefghijklmnopqrst-auth-token", {
      access_token: stale,
      refresh_token: "r-server-refresh",
      expires_at: Math.floor(Date.now() / 1000) + 10,
      token_type: "bearer",
      user: { id: USER },
    })
      .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
      .join("; ");
    const request = () =>
      new Request("https://app.test/", { headers: { cookie } });

    expect((await server.context(request())).auth).toMatchObject({
      kind: "user",
    });
    expect(onRefresh).not.toHaveBeenCalled();
    const refreshed = await server.context(request(), { refresh: true });
    expect(refreshed.auth).toEqual({ kind: "anon", reason: "signed_out" });
    expect(onRefresh).toHaveBeenCalledWith(
      expect.objectContaining({ ok: false, shared: false }),
    );
    expect(events).toEqual([expect.objectContaining({ ok: false })]);
  });
});
