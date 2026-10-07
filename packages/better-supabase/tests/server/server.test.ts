import * as v from "valibot";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type { AuthEvent, RefreshEvent } from "../../src/core/events.ts";
import type {
  BetterPostgres,
  SessionOptions,
  SqlClaims,
} from "../../src/postgres/pool.ts";

import { writeSession } from "../../src/auth/session.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { postgresExecutor } from "../../src/postgres/executor.ts";
import { createServer, TENANT_HEADER } from "../../src/server/server.ts";
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

  it("sends every client's requests through options.fetch", async () => {
    const global = vi.fn<typeof globalThis.fetch>();
    vi.stubGlobal("fetch", global);
    const traced = vi.fn<typeof globalThis.fetch>(() =>
      Promise.resolve(Response.json([])),
    );
    const server = createServer(defineSupabase(schema), {
      env: { ...env, secretKey: "sb_secret_test" },
      auth: { jwks: signer.jwks as never },
      fetch: traced,
    });
    const token = await signer.sign({
      sub: "11111111-1111-4111-8111-111111111111",
    });
    for (const headers of [{}, { authorization: `Bearer ${token}` }]) {
      const ctx = await server.context(
        new Request("https://api.test/", { headers }),
      );
      await ctx.db.customers.findMany({ select: ["id"] }).orThrow();
    }
    await server
      .admin()
      .customers.findMany({ select: ["id"] })
      .orThrow();
    expect(traced).toHaveBeenCalledTimes(3);
    expect(global).not.toHaveBeenCalled();
  });
});

describe("createServer db options", () => {
  it.each([{}, { db: { timeout: 1000, retry: false } }])(
    "keeps the definition's postgrestVersion gate with %o",
    async (options) => {
      const fetch = vi.fn<typeof globalThis.fetch>(() =>
        Promise.resolve(Response.json([])),
      );
      const server = createServer(
        defineSupabase(schema, { postgrestVersion: "12.2" }),
        { env, auth: { jwks: signer.jwks as never }, fetch, ...options },
      );
      const ctx = await server.context(new Request("https://api.test/"));
      const result = await ctx.db.customers.deleteMany({
        where: { status: "lead" },
        maxAffected: 1,
      });
      expect(result).toMatchObject({
        ok: false,
        error: { kind: "invalid_request" },
      });
      expect(fetch).not.toHaveBeenCalled();
    },
  );

  it("fails a request that outlives db.timeout with a timeout error", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(
      (_input, init) =>
        new Promise((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () => {
            reject(init.signal?.reason);
          });
        }),
    );
    const server = createServer(defineSupabase(schema), {
      env,
      auth: { jwks: signer.jwks as never },
      fetch,
      db: { timeout: 20 },
    });
    const token = await signer.sign({
      sub: "11111111-1111-4111-8111-111111111111",
    });
    const ctx = await server.context(
      new Request("https://api.test/", {
        headers: { authorization: `Bearer ${token}` },
      }),
    );
    const result = await ctx.db.customers.findMany({ select: ["id"] });
    expect(result).toMatchObject({ ok: false, error: { kind: "timeout" } });
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
    const organization = "22222222-2222-4222-8222-222222222222";
    const permdock = {
      tenant_id: organization,
      user_role: "member",
      roles: ["support"],
      memberships: [
        {
          scope: "project",
          id: "p1",
          within: { organization: organization },
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
  const sessions: (SessionOptions | undefined)[] = [];
  // SAFETY: the server only calls executorFor; the executor only calls queryRaw.
  const postgres = {
    admin: fake.sql,
    anon: fake.sql,
    executorFor: (value: SqlClaims, session?: SessionOptions) => {
      claims.push(value);
      sessions.push(session);
      return postgresExecutor(fake.sql);
    },
  } as unknown as BetterPostgres;
  return { postgres, claims, sessions, fake };
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

  it("runs a user's db on PostgREST with the token, key and headers", async () => {
    const { sent } = stubFetch();
    const server = createServer(defineSupabase(schema), { env });
    const ctx = server.contextFor(user("user-token"));
    await ctx.db.customers.findMany({ limit: 1 });
    expect(sent(0).url).toMatch(
      /^https:\/\/abcdefghijklmnopqrst\.supabase\.co\/rest\/v1\/customers\?/,
    );
    expect(sent(0).headers.get("authorization")).toBe("Bearer user-token");
    expect(sent(0).headers.get("apikey")).toBe("sb_publishable_test");
    const db = server.dbFor(user("user-token"));
    await db.customers.findMany({ limit: 1 });
    expect(sent(1).headers.get("authorization")).toBe("Bearer user-token");
    expect(db.$client).toBe(db.$client);
    expect(typeof db.$client.storage.from).toBe("function");
  });

  it("builds contexts from one resolution", async () => {
    const server = createServer(defineSupabase(schema), { env });
    const request = new Request("https://app.test/");
    const resolution = await server.resolve(request);
    const first = server.contextFromResolution(resolution, request);
    const second = server.contextFromResolution(resolution, request);
    expect(first.resolution).toBe(resolution);
    expect(second.auth).toBe(first.auth);
    expect(first.db).not.toBe(second.db);
  });

  it("reuses the context of a request for the same refresh and cookies options", async () => {
    const server = createServer(defineSupabase(schema), { env });
    const request = new Request("https://app.test/");
    const first = await server.context(request);
    expect(await server.context(request, { refresh: false })).toBe(first);
    expect(await server.context(request, { refresh: true })).not.toBe(first);
    expect(await server.context(request, { tenant: "t1" })).not.toBe(first);
    expect(await server.context(new Request("https://app.test/"))).not.toBe(
      first,
    );
  });

  it("prefetches the JWKS when asked, and never with an inline JWKS", async () => {
    const { fetch } = stubFetch();
    createServer(defineSupabase(schema), {
      env: { ...env, jwksUrl: new URL("https://prefetch.test/jwks.json") },
      prefetchJwks: true,
    });
    await vi.waitFor(() => {
      expect(
        fetch.mock.calls.some(([input]) =>
          String(input).startsWith("https://prefetch.test/jwks.json"),
        ),
      ).toBe(true);
    });
    fetch.mockClear();
    createServer(defineSupabase(schema), {
      env,
      prefetchJwks: true,
      auth: { jwks: { keys: [] } },
    });
    await new Promise((resolve) => {
      setTimeout(resolve, 10);
    });
    expect(fetch).not.toHaveBeenCalled();
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

describe("createServer tenant", () => {
  const TENANT = "33333333-3333-4333-8333-333333333333";

  it("sends the resolved tenant as context, setting and header", async () => {
    const { sent } = stubFetch();
    const { postgres, sessions } = fakePostgres();
    const resolver = vi.fn(
      async (request: Request) =>
        new URL(request.url).searchParams.get("organization") ?? undefined,
    );
    const server = createServer(defineSupabase(schema), {
      env,
      postgres,
      tenant: resolver,
    });
    const ctx = await server.context(
      new Request(`https://app.test/?organization=${TENANT}`),
    );
    expect(resolver).toHaveBeenCalledWith(expect.any(Request), ctx.auth);
    expect(ctx.db.$context.tenant).toBe(TENANT);
    await ctx.db.customers.findMany({ select: ["id"] }).orThrow();
    expect(sent(0).headers.get(TENANT_HEADER)).toBe(TENANT);
    await ctx.sql!.customers.findMany({ select: ["id"] }).orThrow();
    expect(sessions).toEqual([
      { settings: { "better_supabase.tenant": TENANT } },
    ]);

    const none = await server.context(new Request("https://app.test/"));
    expect(none.db.$context.tenant).toBeUndefined();
    await none.sql!.customers.findMany({ select: ["id"] }).orThrow();
    expect(sessions).toHaveLength(2);
    expect(sessions[1]).toBeUndefined();
  });

  it("prefers options.tenant, and needs it for async resolvers without context()", async () => {
    const server = createServer(defineSupabase(schema), {
      env,
      tenant: async () => "from-resolver",
    });
    const request = new Request("https://app.test/");
    const resolution = await server.resolve(request);
    expect(() => server.contextFromResolution(resolution, request)).toThrow(
      "ServerOptions.tenant returned a promise",
    );
    expect(
      server.contextFromResolution(resolution, request, { tenant: TENANT }).db
        .$context.tenant,
    ).toBe(TENANT);
    expect(
      (await server.context(request, { tenant: "explicit" })).db.$context
        .tenant,
    ).toBe("explicit");
    expect(server.contextFor(anon, { tenant: TENANT }).db.$context.tenant).toBe(
      TENANT,
    );

    const sync = createServer(defineSupabase(schema), {
      env,
      tenant: () => "sync",
    });
    expect(
      sync.contextFromResolution(resolution, request).db.$context.tenant,
    ).toBe("sync");
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
        act: {
          kind: "impersonation",
          sub: "admin-1",
          reason: "support ticket",
        },
      },
    ]);
  });
});

describe("createServer forContext", () => {
  const TENANT = "33333333-3333-4333-8333-333333333333";
  const userActor = { id: USER, kind: "user" as const };

  it("runs as the recorded user, scoped to the recorded tenant", async () => {
    const { postgres, claims, sessions } = fakePostgres();
    const server = createServer(defineSupabase(schema), { env, postgres });
    const db = await server
      .forContext({ actor: userActor, tenant: TENANT })
      .orThrow();
    expect(db.$context.actor).toEqual({
      id: USER,
      kind: "user",
      role: "authenticated",
    });
    expect(db.$context.tenant).toBe(TENANT);
    expect(claims).toEqual([
      { role: "authenticated", sub: USER, tenant_id: TENANT },
    ]);
    expect(sessions).toEqual([
      { settings: { "better_supabase.tenant": TENANT } },
    ]);
  });

  it("keeps the impersonator in act", async () => {
    const { postgres, claims } = fakePostgres();
    const server = createServer(defineSupabase(schema), { env, postgres });
    const actor = { ...userActor, impersonator: "admin-1" };
    const db = await server.forContext({ actor }).orThrow();
    await server.forContext({ actor }, { reason: "replay 42" }).orThrow();
    expect(db.$context.actor).toMatchObject({ impersonator: "admin-1" });
    expect(claims.map((value) => value["act"])).toEqual([
      { kind: "impersonation", sub: "admin-1", reason: "job" },
      { kind: "impersonation", sub: "admin-1", reason: "replay 42" },
    ]);
  });

  it("keeps a recorded support session read-only, with its act claim", async () => {
    const { postgres, claims, sessions } = fakePostgres();
    const server = createServer(defineSupabase(schema), { env, postgres });
    const act = {
      kind: "support",
      sub: "admin-1",
      session_id: "s-1",
      read_only: true,
    };
    const actor = { ...userActor, impersonator: "admin-1" };
    await server.forContext({ actor, claims: { act } }).orThrow();
    await server
      .forContext({ actor, claims: { act: { ...act, read_only: false } } })
      .orThrow();
    expect(claims.map((value) => value["act"])).toEqual([
      act,
      { ...act, read_only: false },
    ]);
    expect(sessions).toEqual([{ readOnly: true }, undefined]);
  });

  it("refuses a context whose act claim is not a valid chain", async () => {
    const { postgres, claims } = fakePostgres();
    const server = createServer(defineSupabase(schema), { env, postgres });
    const result = await server.forContext({
      actor: userActor,
      claims: { act: { kind: "root", sub: "admin-1" } },
    });
    expect(result.error).toMatchObject({ kind: "forbidden" });
    expect(claims).toEqual([]);
  });

  it("adds claimsFor, which can't replace sub, role or the tenant", async () => {
    const { postgres, claims } = fakePostgres();
    const claimsFor = vi.fn(async () => ({
      sub: "someone-else",
      role: "service_role",
      tenant_id: "other",
      user_role: "admin",
    }));
    const server = createServer(defineSupabase(schema), {
      env,
      postgres,
      claimsFor,
    });
    const context = { actor: userActor, tenant: TENANT };
    await server.forContext(context).orThrow();
    expect(claimsFor).toHaveBeenCalledWith(USER, context);
    expect(claims).toEqual([
      {
        sub: USER,
        role: "authenticated",
        tenant_id: TENANT,
        user_role: "admin",
      },
    ]);

    const sync = createServer(defineSupabase(schema), {
      env,
      postgres,
      claimsFor: () => ({ organization_ids: [TENANT] }),
    });
    await sync.forContext({ actor: userActor }).orThrow();
    expect(claims[1]).toEqual({
      organization_ids: [TENANT],
      role: "authenticated",
      sub: USER,
    });
  });

  it("refuses contexts without a user and never falls back to admin", async () => {
    const { postgres, claims } = fakePostgres();
    const server = createServer(defineSupabase(schema), { env, postgres });
    for (const [context, kind] of [
      [{}, "none"],
      [{ actor: { id: "service", kind: "service" as const } }, "service"],
      [{ actor: { id: "anon", kind: "anon" as const } }, "anon"],
    ] as const) {
      const result = await server.forContext(context);
      expect(result.error).toMatchObject({ kind: "forbidden" });
      expect(result.error?.message).toContain(`got ${kind}`);
    }
    expect(claims).toEqual([]);
  });

  it("fails with invalid_request without postgres", async () => {
    const server = createServer(defineSupabase(schema), { env });
    const result = await server.forContext({ actor: userActor });
    expect(result.error).toMatchObject({
      kind: "invalid_request",
      message:
        "Direct Postgres access needs createServer(betterSupabase, { postgres: createPostgres() })",
    });
  });

  it("returns claimsFor failures as a result", async () => {
    const { postgres } = fakePostgres();
    const server = createServer(defineSupabase(schema), {
      env,
      postgres,
      claimsFor: () => Promise.reject(new Error("profile lookup failed")),
    });
    const result = await server.forContext({ actor: userActor });
    expect(result.ok).toBe(false);
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
      { source: "bearer", ok: true, userId: USER, rawSource: "bearer" },
      { source: "cookie", ok: true, userId: USER, rawSource: "cookie" },
      { source: "bearer", ok: true },
      { source: "none", ok: true, reason: "none" },
      { source: "none", ok: false, reason: "token" },
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
