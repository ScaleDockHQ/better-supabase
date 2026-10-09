import { Hono } from "hono";
import { describe, expect, it } from "vitest";

import type { AuthState } from "../../../src/auth/resolve.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";
import type {
  BetterPostgres,
  SessionOptions,
  SqlClaims,
} from "../../../src/postgres/pool.ts";

import { toSession } from "../../../src/auth/view.ts";
import {
  apiKeyChecksum,
  apiKeyClaims,
  apiKeyResolver,
  createApiKeys,
  parseApiKey,
} from "../../../src/blocks/api-keys/index.ts";
import { sha256Hex } from "../../../src/core/block-helpers.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { ok } from "../../../src/core/result.ts";
import { createHono, type HonoEnv } from "../../../src/hono/index.ts";
import { postgresExecutor } from "../../../src/postgres/executor.ts";
import { fakeSql } from "../../fixtures/fake-sql.ts";
import {
  type Functions,
  type Models,
  schema,
} from "../../fixtures/generated-camel.ts";

const ORG = "11111111-1111-4111-8111-111111111111";
const USER = "22222222-2222-4222-8222-222222222222";

const row = (extra: Record<string, unknown> = {}) => ({
  id: "33333333-3333-4333-8333-333333333333",
  organization_id: ORG,
  user_id: null,
  name: "CI",
  prefix: "bs",
  public_id: "0123456789abcdef",
  scopes: ["deals:read"],
  rate_limit: 60,
  expires_at: null,
  last_used_at: "2026-10-06T10:00:00Z",
  revoked_at: null,
  rotated_from: null,
  created_by: USER,
  created_at: "2026-10-06T09:00:00Z",
  ...extra,
});

function fakeTransport(
  answer: (fn: string, args: Record<string, unknown>) => unknown,
) {
  const calls: [string, string, Record<string, unknown>][] = [];
  const transport: BlockTransport = {
    async call(schemaName, fn, args) {
      calls.push([schemaName, fn, { ...args }]);
      return answer(fn, { ...args });
    },
  };
  return { transport, calls };
}

describe("parseApiKey", () => {
  it("splits keys and refuses anything else", () => {
    const secret = "a".repeat(43);
    expect(parseApiKey(`bs_0123456789abcdef_${secret}`)).toEqual({
      prefix: "bs",
      publicId: "0123456789abcdef",
      secret,
      checksum: false,
    });
    expect(parseApiKey("eyJhbGciOi.eyJzdWIi.sig")).toBeUndefined();
    expect(parseApiKey(`bs_0123_${secret}`)).toBeUndefined();
  });

  it("checks the CRC-32 checksum at the end of a key", () => {
    const secret = "A1".repeat(21) + "z";
    const body = `key_0123456789abcdef_${secret}`;
    const checked = `${body}${apiKeyChecksum(body)}`;
    expect(parseApiKey(checked)).toEqual({
      prefix: "key",
      publicId: "0123456789abcdef",
      secret,
      checksum: true,
    });
    const typo = `${checked.slice(0, -1)}${checked.endsWith("a") ? "b" : "a"}`;
    expect(parseApiKey(typo)).toBeUndefined();
    // A key from another generator that uses the same checksum.
    const foreign = "acme_0123456789abcdef_" + "Lx9".repeat(14) + "q";
    expect(parseApiKey(`${foreign}${apiKeyChecksum(foreign)}`)).toMatchObject({
      prefix: "acme",
      checksum: true,
    });
    expect(apiKeyChecksum("")).toBe("AAAAAA");
    expect(apiKeyChecksum("123456789")).toMatch(/^[A-Za-z0-9]{6}$/);
  });
});

describe("apiKeyClaims", () => {
  const key = (extra: Record<string, unknown> = {}) =>
    ({
      id: "k",
      name: "CI",
      prefix: "bs",
      publicId: "0123456789abcdef",
      scopes: ["task.read", "*"],
      createdAt: Temporal.Instant.from("2026-10-06T09:00:00Z"),
      state: "active",
      ...extra,
    }) as Parameters<typeof apiKeyClaims>[0];

  it("writes the module's claim, and a provider's with options.claim", () => {
    expect(apiKeyClaims(key({ organizationId: ORG }))).toEqual({
      sub: "",
      role: "authenticated",
      aud: "authenticated",
      api_key: {
        id: "k",
        name: "CI",
        scopes: ["task.read", "*"],
        organization_id: ORG,
      },
    });
    expect(
      apiKeyClaims(key({ organizationId: ORG }), {
        claim: { name: "api_key", serviceRoles: ["developer"] },
        allPermissions: ["task.read", "task.update"],
      })["api_key"],
    ).toEqual({
      id: "k",
      name: "CI",
      scopes: ["task.read", "task.update"],
      organization_id: ORG,
      tenant: ORG,
      roles: ["developer"],
    });
    expect(
      apiKeyClaims(key({ organizationId: ORG }), {
        claim: { name: "authz_key", tenant: "organization_id" },
        serviceRoles: () => ["integration"],
      })["authz_key"],
    ).toEqual({
      id: "k",
      name: "CI",
      scopes: ["task.read"],
      organization_id: ORG,
      roles: ["integration"],
    });
  });

  it("narrows a personal key limited to a tenant with the tenant claim", () => {
    const claims = apiKeyClaims(key({ userId: USER, organizationId: ORG }), {
      claim: { name: "api_key" },
      tenantClaim: "tenant_id",
    });
    expect(claims).toMatchObject({ sub: USER, tenant_id: ORG });
    expect(claims["api_key"]).not.toHaveProperty("tenant");
    expect(claims["api_key"]).not.toHaveProperty("roles");
  });
});

describe("createApiKeys", () => {
  it("sends only the secret's hash and returns the token once", async () => {
    const { transport, calls } = fakeTransport(() => row());
    const keys = createApiKeys({ transport, prefix: "acme" });
    const created = await keys
      .create({
        name: "CI",
        organizationId: ORG,
        scopes: ["deals:read"],
        expiresAt: Temporal.Instant.from("2027-01-01T00:00:00Z"),
        rateLimit: 60,
      })
      .orThrow();
    const parsed = parseApiKey(created.token)!;
    expect(parsed.prefix).toBe("acme");
    const [, fn, args] = calls[0]!;
    expect(fn).toBe("create_api_key");
    expect(args).toMatchObject({
      name: "CI",
      public_id: parsed.publicId,
      secret_hash: await sha256Hex(parsed.secret),
      tenant: ORG,
      personal: false,
      expires_at: "2027-01-01T00:00:00Z",
      prefix: "acme",
    });
    expect(JSON.stringify(args)).not.toContain(parsed.secret);
    expect(created.key).toMatchObject({
      organizationId: ORG,
      scopes: ["deals:read"],
      rateLimit: 60,
      createdBy: USER,
    });
    expect(created.key.lastUsedAt?.toString()).toBe("2026-10-06T10:00:00Z");
    expect(() => createApiKeys({ transport, prefix: "Bad_" })).toThrow(
      /prefix/,
    );
  });

  it("lists, revokes and rotates with a grace period", async () => {
    const { transport, calls } = fakeTransport((fn) =>
      fn === "list_api_keys"
        ? [
            row(),
            row({
              user_id: USER,
              rotated_from: "x",
              revoked_at: "2026-10-07T00:00:00Z",
            }),
          ]
        : fn === "revoke_api_key"
          ? true
          : row({ rotated_from: "33333333-3333-4333-8333-333333333333" }),
    );
    const keys = createApiKeys({ transport });
    const listed = await keys.list(ORG).orThrow();
    expect(listed[1]).toMatchObject({ userId: USER, rotatedFrom: "x" });
    expect(listed.map((key) => key.state)).toEqual(["active", "revoked"]);
    expect(await keys.list().orThrow()).toHaveLength(2);
    expect(await keys.revoke("k").orThrow()).toBe(true);
    const rotated = await keys
      .rotate("k", { grace: Temporal.Duration.from({ hours: 2 }) })
      .orThrow();
    expect(rotated.token).toMatch(/^bs_/);
    expect(calls.at(-1)?.[2]).toMatchObject({ key: "k", grace: "PT2H" });
    await keys.rotate("k");
    expect(calls.at(-1)?.[2]).toMatchObject({ grace: "P1D" });
  });

  it("reads the state and successor the database computed", async () => {
    const future = Temporal.Now.instant().add({ hours: 1 }).toString();
    const past = "2020-01-01T00:00:00Z";
    const { transport } = fakeTransport(() => [
      row({ state: "grace", successor_id: "next", revoked_at: future }),
      row({ state: "expired", expires_at: past }),
      row({ revoked_at: future }),
      row({ expires_at: past }),
      row({ state: "unknown" }),
    ]);
    const listed = await createApiKeys({ transport }).list(ORG).orThrow();
    expect(listed.map((key) => key.state)).toEqual([
      "grace",
      "expired",
      "grace",
      "expired",
      "active",
    ]);
    expect(listed[0]?.successorId).toBe("next");
    expect(listed[1]).not.toHaveProperty("successorId");
  });

  it("verifies tokens and maps each status", async () => {
    const answers = [
      { status: "ok", key: row() },
      { status: "rate_limited", retry_after: 12 },
      { status: "invalid" },
    ];
    const { transport, calls } = fakeTransport(() => answers.shift());
    const keys = createApiKeys({ transport });
    const token = `bs_0123456789abcdef_${"b".repeat(43)}`;
    expect(await keys.verify(token).orThrow()).toMatchObject({
      status: "ok",
      key: { publicId: "0123456789abcdef" },
    });
    expect(calls[0]?.[2]).toEqual({
      public_id: "0123456789abcdef",
      secret_hash: await sha256Hex("b".repeat(43)),
    });
    expect(await keys.verify(token).orThrow()).toEqual({
      status: "rate_limited",
      retryAfter: 12,
    });
    expect(await keys.verify(token).orThrow()).toEqual({ status: "invalid" });
    expect(
      await keys.verify(`other_0123456789abcdef_${"b".repeat(43)}`).orThrow(),
    ).toEqual({ status: "invalid" });
    expect(calls).toHaveLength(3);
  });
});

describe("apiKeyResolver", () => {
  const token = `bs_0123456789abcdef_${"c".repeat(43)}`;
  const resolverWith = (answer: unknown) =>
    apiKeyResolver({
      keys: createApiKeys({ transport: fakeTransport(() => answer).transport }),
    });

  it("reads x-api-key or a key-shaped Bearer token, and passes JWTs on", async () => {
    const resolver = resolverWith({
      status: "ok",
      key: row({ user_id: USER }),
    });
    const state = await resolver.resolve(
      new Request("https://x.test", { headers: { "x-api-key": token } }),
    );
    expect(state).toMatchObject({
      kind: "apiKey",
      organizationId: ORG,
      userId: USER,
      scopes: ["deals:read"],
      createdAt: Temporal.Instant.from("2026-10-06T09:00:00Z"),
      createdBy: USER,
      claims: {
        sub: USER,
        role: "authenticated",
        api_key: { organization_id: ORG, scopes: ["deals:read"] },
      },
    });
    expect(toSession(state as AuthState)).toMatchObject({
      kind: "apiKey",
      createdAt:
        Temporal.Instant.from("2026-10-06T09:00:00Z").epochMilliseconds / 1000,
      createdBy: USER,
    });
    expect(
      await resolver.resolve(
        new Request("https://x.test", {
          headers: { authorization: `Bearer ${token}` },
        }),
      ),
    ).toMatchObject({ kind: "apiKey" });
    expect(
      await resolver.resolve(
        new Request("https://x.test", {
          headers: { authorization: "Bearer eyJ.a.b" },
        }),
      ),
    ).toBeUndefined();
    expect(
      await resolver.resolve(new Request("https://x.test")),
    ).toBeUndefined();
  });

  it("answers invalid and rate-limited keys with their errors", async () => {
    const request = () =>
      new Request("https://x.test", { headers: { "x-api-key": token } });
    expect(
      await resolverWith({ status: "invalid" }).resolve(request()),
    ).toMatchObject({
      kind: "invalid",
      error: { kind: "unauthorized", code: "INVALID_API_KEY" },
    });
    expect(
      await resolverWith({ status: "rate_limited", retry_after: 3 }).resolve(
        request(),
      ),
    ).toMatchObject({
      kind: "invalid",
      error: { kind: "rate_limited", retryAfter: 3 },
    });
    const failing = apiKeyResolver({
      keys: {
        verify: () =>
          createApiKeys({
            transport: {
              call: () => Promise.reject(new Error("down")),
            },
          }).verify(token),
      },
    });
    expect(await failing.resolve(request())).toMatchObject({ kind: "invalid" });
  });
});

describe("API keys in a server", () => {
  const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
  const env = {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  };
  const token = `bs_0123456789abcdef_${"d".repeat(43)}`;

  it("runs queries over Postgres with the key's claims and tenant", async () => {
    const fake = fakeSql();
    const claims: SqlClaims[] = [];
    const sessions: (SessionOptions | undefined)[] = [];
    // SAFETY: the server only calls executorFor; the executor only calls queryRaw.
    const postgres = {
      executorFor: (value: SqlClaims, session?: SessionOptions) => {
        claims.push(value);
        sessions.push(session);
        return postgresExecutor(fake.sql);
      },
    } as unknown as BetterPostgres;
    const keys = createApiKeys({
      transport: fakeTransport(() => ({ status: "ok", key: row() })).transport,
    });
    const bs = createHono(defineSupabase(schema), {
      env,
      postgres,
      auth: { resolvers: [apiKeyResolver({ keys })] },
    });
    type Env = HonoEnv<Models, Functions, unknown>;
    const app = new Hono<Env>()
      .onError(bs.onError)
      .use(
        "/keys/*",
        bs.middleware({ allow: ["apiKey"], scopes: ["deals:read"] }),
      )
      .use(
        "/write/*",
        bs.middleware({ allow: ["apiKey"], scopes: ["deals:write"] }),
      )
      .use("/users/*", bs.middleware())
      .get(
        "/keys/who",
        bs.handler(async (_c, ctx) => {
          void ctx.db;
          let client = "available";
          try {
            void ctx.db.$client;
          } catch {
            client = "unavailable";
          }
          let supabase = "available";
          try {
            void ctx.supabase;
          } catch {
            supabase = "unavailable";
          }
          return ok({
            kind: ctx.auth.kind,
            supabase,
            client,
            sql: ctx.sql !== undefined,
          });
        }),
      )
      .get("/write/x", (c) => c.json({}))
      .get("/users/x", (c) => c.json({}));

    const headers = { "x-api-key": token };
    const who = await app.request("/keys/who", { headers });
    expect(who.status).toBe(200);
    expect(await who.json()).toEqual({
      kind: "apiKey",
      supabase: "unavailable",
      client: "unavailable",
      sql: true,
    });
    expect(claims[0]).toMatchObject({
      sub: "",
      role: "authenticated",
      api_key: { organization_id: ORG },
    });
    expect(sessions[0]).toEqual({
      settings: { "better_supabase.tenant": ORG },
    });
    expect((await app.request("/write/x", { headers })).status).toBe(403);
    expect((await app.request("/users/x", { headers })).status).toBe(403);
  });
});
