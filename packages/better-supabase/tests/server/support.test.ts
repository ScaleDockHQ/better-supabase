import { AsyncLocalStorage } from "node:async_hooks";
import * as v from "valibot";
import { describe, expect, it, vi } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type { BlockEvent } from "../../src/core/block-events.ts";
import type {
  BetterPostgres,
  SessionOptions,
  SqlClaims,
} from "../../src/postgres/pool.ts";

import { createOrganizations } from "../../src/blocks/organizations/index.ts";
import { dbTransport } from "../../src/core/block-transport.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { postgresExecutor } from "../../src/postgres/executor.ts";
import { createServer } from "../../src/server/server.ts";
import {
  type SupportOptions,
  supportSessions as denyingSupportSessions,
} from "../../src/server/support.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { fakeSql, pgError } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { memorySupportStore } from "../fixtures/support-store.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const signer = await createTestSigner();

// These tests cover sessions once allowed; tests/server/support-approval.test.ts
// covers the deny-by-default authorize and the second admin.
const supportSessions = (options: SupportOptions) =>
  denyingSupportSessions({
    authorize: () => true,
    ...options,
    policy: { approval: "none", ...options.policy },
  });

const ADMIN = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const TARGET = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

function fakePostgres(rules: Parameters<typeof fakeSql>[0] = []) {
  const fake = fakeSql(rules);
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
    asUser: (value: SqlClaims, session?: SessionOptions) => {
      claims.push(value);
      sessions.push(session);

      return fake.sql;
    },
  } as unknown as BetterPostgres;

  return { postgres, claims, sessions, fake };
}

const admin = (claims: Record<string, unknown> = {}): AuthState => ({
  kind: "user",
  token: "t",
  claims: { sub: ADMIN, role: "authenticated", ...claims },
  user: { id: ADMIN, role: "authenticated", email: "admin@acme.test" },
  source: "bearer",
  expiresAt: null,
});

function setup(
  options: Parameters<typeof createServer>[1] = {},
  rules: Parameters<typeof fakeSql>[0] = [],
) {
  const betterSupabase = defineSupabase(schema);
  const events: BlockEvent[] = [];
  betterSupabase.events.on("block", (event) => events.push(event));

  const store = memorySupportStore({
    [TARGET]: {
      role: "authenticated",
      email: "member@acme.test",
      organization: "o1",
    },
  });

  const pg = fakePostgres(rules);

  const server = createServer(betterSupabase, {
    env,
    auth: { jwks: signer.jwks as never },
    postgres: pg.postgres,
    support: supportSessions({ store }),
    ...options,
  });

  return { server, store, events, pg };
}

const request = async (cookie?: string) =>
  new Request("https://app.test/", {
    headers: {
      authorization: `Bearer ${await signer.sign({ sub: ADMIN, role: "authenticated", email: "admin@acme.test" })}`,
      ...(cookie ? { cookie } : {}),
    },
  });

describe("support sessions on the server", () => {
  it("needs postgres", () => {
    expect(() =>
      createServer(defineSupabase(schema), {
        env,
        support: supportSessions({ store: memorySupportStore() }),
      }),
    ).toThrow(/postgres/);
  });

  it("fails every call without support options", async () => {
    const server = createServer(defineSupabase(schema), { env });

    const started = await server.support.start(admin(), {
      targetUserId: TARGET,
      reason: "r",
    });

    expect(started.error?.message).toMatch(/supportSessions\(\{ store \}\)/);
    expect((await server.support.stop(admin(), "s")).ok).toBe(false);
    expect((await server.support.revoke(admin(), "s")).ok).toBe(false);
    expect((await server.support.list(admin())).ok).toBe(false);
    expect(
      await server.support.current(new Request("https://a.test/"), admin()),
    ).toBeUndefined();
    expect(
      server.support.sessionIdOf(
        new Request("https://a.test/", { headers: { cookie: "bs-support=s" } }),
      ),
    ).toBeUndefined();
    expect(server.support.clearCookie()).toMatch(/Max-Age=0/);
  });

  it("refuses starts that break the policy and reports them", async () => {
    const { server, events } = setup({
      support: supportSessions({
        store: memorySupportStore(),
        policy: { maxTtl: 600 },
      }),
    });

    const codes = [];

    for (const [auth, input] of [
      [admin(), { targetUserId: TARGET }],
      [admin(), { targetUserId: ADMIN, reason: "r" }],
      [admin(), { targetUserId: TARGET, reason: "r", ttl: 601 }],
      [admin({ act: { sub: "x" } }), { targetUserId: TARGET, reason: "r" }],
    ] as const) {
      const result = await server.support.start(auth, input);
      codes.push(result.error?.code);
    }

    expect(codes).toEqual([
      "SUPPORT_REASON_REQUIRED",
      "SUPPORT_SELF",
      "SUPPORT_TTL",
      "SUPPORT_NESTED",
    ]);
    expect(events.map((event) => event.type)).toEqual(
      Array.from({ length: 4 }, () => "support.denied"),
    );
    expect(events[0]?.data).toMatchObject({ denial: "policy" });

    const anon = await server.support.start(
      { kind: "anon", reason: "none" },
      { targetUserId: TARGET, reason: "r" },
    );

    expect(anon.error?.kind).toBe("unauthorized");
  });

  it("asks authorize, treating a throw as a deny", async () => {
    const calls: unknown[] = [];

    for (const authorize of [
      () => false,
      () => {
        throw new Error("boom");
      },
    ]) {
      const { server, events } = setup({
        support: supportSessions({
          store: memorySupportStore(),
          authorize: (input) => {
            calls.push(input.targetUserId);

            return authorize();
          },
        }),
      });

      const result = await server.support.start(admin(), {
        targetUserId: TARGET,
        reason: "r",
      });

      expect(result.error).toMatchObject({
        kind: "forbidden",
        code: "SUPPORT_FORBIDDEN",
      });
      expect(events[0]?.data).toMatchObject({ denial: "authorize" });
    }

    expect(calls).toEqual([TARGET, TARGET]);
  });

  it("reports a refusal by the store's permission check", async () => {
    const store = memorySupportStore();

    const { server, events } = setup({
      support: supportSessions({
        store: {
          ...store,
          start: () =>
            Promise.reject(
              pgError("42501", "Not allowed", { hint: "SUPPORT_FORBIDDEN" }),
            ),
        },
      }),
    });

    const result = await server.support.start(admin(), {
      targetUserId: TARGET,
      reason: "r",
    });

    expect(result.error?.code).toBe("42501");
    expect(events[0]?.data).toMatchObject({ denial: "permission" });
  });

  it("runs the admin's requests as the target, read-only, until stopped", async () => {
    const { server, events, pg } = setup();

    const started = await server.support
      .start(admin(), {
        targetUserId: TARGET,
        reason: "ticket 9",
        readOnly: false,
        metadata: { ticket: 9 },
      })
      .orThrow();

    expect(started.session.readOnly).toBe(true);
    expect(started.cookie).toMatch(/^bs-support=[^;]+; Path=\/; Max-Age=1800;/);
    expect(events.at(-1)).toMatchObject({
      type: "support.started",
      actorId: ADMIN,
      subject: `support_sessions/${started.session.id}`,
    });

    const cookie = `bs-support=${started.session.id}`;
    const ctx = await server.context(await request(cookie));
    expect(ctx.support?.admin).toEqual({
      id: ADMIN,
      email: "admin@acme.test",
    });
    expect(ctx.auth).toMatchObject({
      kind: "user",
      source: "support",
      user: { id: TARGET, email: "member@acme.test" },
    });
    expect(ctx.resolution.auth).toMatchObject({ user: { id: ADMIN } });
    expect(() => ctx.supabase).toThrow(/support session/);
    expect(() => ctx.db.$client).toThrow(/support session/);
    await ctx.db.customers.findMany({ select: ["id"] }).orThrow();
    await ctx.sql!.customers.findMany({ select: ["id"] }).orThrow();
    expect(pg.claims[0]).toEqual({
      role: "authenticated",
      email: "member@acme.test",
      organization: "o1",
      sub: TARGET,
      act: {
        kind: "support",
        sub: ADMIN,
        reason: "ticket 9",
        session_id: started.session.id,
        read_only: true,
      },
    });
    expect(pg.sessions[0]).toEqual({
      readOnly: true,
      settings: {
        "better_supabase.request_id": ctx.requestId,
        "better_supabase.correlation_id": ctx.requestId,
      },
    });
    expect(ctx.stats().calls).toBe(2);
    expect(ctx.apply(new Response()).status).toBe(200);

    const listed = await server.support
      .list(admin(), { adminId: ADMIN })
      .orThrow();

    expect(listed).toHaveLength(1);

    const stopped = await server.support
      .stop(admin(), started.session.id)
      .orThrow();

    expect(stopped.ended).toBe(true);
    expect(stopped.cookie).toContain("Max-Age=0");
    expect(events.at(-1)?.type).toBe("support.ended");
    const after = await server.context(await request(cookie));
    expect(after.support).toBeUndefined();
    expect(after.auth).toMatchObject({ user: { id: ADMIN } });
    expect(
      (await server.support.stop(admin(), started.session.id)).data?.ended,
    ).toBe(false);
    expect(
      (await server.support.stop({ kind: "anon", reason: "none" }, "x")).error
        ?.kind,
    ).toBe("unauthorized");
  });

  it("runs a block over ctx.db as the target with dbTransport", async () => {
    const { server, pg } = setup({}, [
      ["pg_catalog.pg_proc", [{ returns_set: false, returns_void: false }]],
      [
        "bs_call",
        () => ({
          throws: pgError("42501", "Not a member", {
            hint: "ORGANIZATION_FORBIDDEN",
          }),
        }),
      ],
    ]);

    const started = await server.support
      .start(admin(), { targetUserId: TARGET, reason: "ticket 9" })
      .orThrow();

    const ctx = await server.context(
      await request(`bs-support=${started.session.id}`),
    );

    expect(() => ctx.db.$client).toThrow(/support session/);

    const organizations = createOrganizations({
      transport: dbTransport(ctx.db, { schema: "api" }),
    });

    expect(await organizations.leave("o1")).toMatchObject({
      ok: false,
      error: { kind: "forbidden", hint: "ORGANIZATION_FORBIDDEN" },
    });
    expect(pg.claims[0]).toMatchObject({
      sub: TARGET,
      act: { kind: "support", session_id: started.session.id },
    });
    expect(pg.sessions[0]).toMatchObject({ readOnly: true });
    expect(pg.fake.texts().at(-1)).toContain('"api"."leave_organization"(');
  });

  it("allows writes only when the policy and the start agree", async () => {
    const { server, pg } = setup({
      support: supportSessions({
        store: memorySupportStore(),
        policy: { readOnly: "default" },
        claims: () => ({ role: "authenticated", custom: true }),
      }),
    });

    const { session } = await server.support
      .start(admin(), { targetUserId: TARGET, reason: "fix", readOnly: false })
      .orThrow();

    expect(session.readOnly).toBe(false);

    const ctx = await server.context(
      await request(`bs-support=${session.id}`),
      { tenant: "t1" },
    );

    await ctx.sql!.customers.findMany({ select: ["id"] }).orThrow();
    expect(pg.claims[0]).toMatchObject({ custom: true });
    expect(pg.sessions[0]).toEqual({
      settings: {
        "better_supabase.request_id": ctx.requestId,
        "better_supabase.correlation_id": ctx.requestId,
        "better_supabase.tenant": "t1",
      },
    });
    expect(ctx.auth.kind === "user" && ctx.auth.claims["act"]).toMatchObject({
      read_only: false,
    });
  });

  it("keeps a writable stored session read-only under the always policy", async () => {
    const { server, store } = setup();

    const session = await store.start({
      adminId: ADMIN,
      adminClaims: {},
      targetUserId: TARGET,
      reason: "r",
      ttlSeconds: 60,
      readOnly: false,
      metadata: {},
    });

    const cookie = new Request("https://a.test/", {
      headers: { cookie: `bs-support=${session.id}` },
    });

    const active = await server.support.current(cookie, admin());
    expect(active?.session.readOnly).toBe(true);
    expect(active?.claims["act"]).toMatchObject({ read_only: true });
  });

  it("resolves a session id the app keeps in its own request context", async () => {
    const store = new AsyncLocalStorage<{ supportSessionId?: string }>();

    const { server, pg } = setup({
      support: supportSessions({
        store: memorySupportStore({ [TARGET]: { role: "authenticated" } }),
        sessionId: () => store.getStore()?.supportSessionId,
      }),
    });

    const { session } = await server.support
      .start(admin(), { targetUserId: TARGET, reason: "r" })
      .orThrow();

    const bare = new Request("https://a.test/");
    expect(server.support.sessionIdOf(bare)).toBeUndefined();
    await store.run({ supportSessionId: session.id }, async () => {
      expect(server.support.sessionIdOf(bare)).toBe(session.id);
      expect((await server.support.current(bare, admin()))?.session.id).toBe(
        session.id,
      );
    });
    expect(await server.support.resolve("", admin())).toBeUndefined();
    const active = await server.support.resolve(session.id, admin());

    if (!active) {
      throw new Error("no support session");
    }

    expect(active.session.targetUserId).toBe(TARGET);
    const auth = server.contextFor(admin(), { support: active }).auth;
    expect(auth.kind === "user" ? auth.user.id : undefined).toBe(TARGET);
    const db = server.dbFor(admin(), {}, { support: active });
    expect(() => db.$client).toThrow(/support session/);
    await db.organizations.findMany().orThrow();
    expect(pg.claims.at(-1)).toMatchObject({ sub: TARGET });
  });

  it("treats a throwing sessionId reader as no session", async () => {
    const { server } = setup({
      support: supportSessions({
        store: memorySupportStore(),
        sessionId: () => {
          throw new Error("no store");
        },
      }),
    });

    expect(
      server.support.sessionIdOf(new Request("https://a.test/")),
    ).toBeUndefined();
  });

  it("loads the support session while the tenant resolver runs", async () => {
    let tenantDone = false;
    let supportStartedFirst = false;

    const { server, store } = setup({
      tenant: async () => {
        await new Promise((resolve) => {
          setTimeout(resolve, 20);
        });
        tenantDone = true;

        return "t1";
      },
    });

    const { session } = await server.support
      .start(admin(), { targetUserId: TARGET, reason: "r" })
      .orThrow();

    const get = store.get.bind(store);
    vi.spyOn(store, "get").mockImplementation((...args) => {
      supportStartedFirst = !tenantDone;

      return get(...args);
    });
    const ctx = await server.context(await request(`bs-support=${session.id}`));
    expect(supportStartedFirst).toBe(true);
    expect(tenantDone).toBe(true);
    expect(ctx.support?.session.id).toBe(session.id);
  });

  it("loads the session every time but reuses the target's claims", async () => {
    const { server, store } = setup();
    const claims = vi.spyOn(store, "claims");
    const get = vi.spyOn(store, "get");

    const { session } = await server.support
      .start(admin(), { targetUserId: TARGET, reason: "r" })
      .orThrow();

    const cookie = new Request("https://a.test/", {
      headers: { cookie: `bs-support=${session.id}` },
    });

    claims.mockClear();
    await server.support.current(cookie, admin());
    await server.support.current(cookie, admin());
    expect(get).toHaveBeenCalledTimes(2);
    expect(claims).toHaveBeenCalledTimes(1);
    await server.support.revoke(admin(), session.id).orThrow();
    expect(await server.support.current(cookie, admin())).toBeUndefined();
  });

  it("ignores the cookie for another admin, a nested token or bad claims", async () => {
    const { server, store } = setup({
      auth: {
        jwks: signer.jwks as never,
        claims: v.object({ organization: v.literal("o2") }),
      },
    });

    const { session } = await server.support
      .start(admin(), { targetUserId: TARGET, reason: "r" })
      .orThrow();

    const cookie = new Request("https://a.test/", {
      headers: { cookie: `bs-support=${session.id}` },
    });

    expect(
      await server.support.current(cookie, admin({ act: { sub: "x" } })),
    ).toBeUndefined();
    expect(
      await server.support.current(cookie, {
        ...admin(),
        user: { id: TARGET },
      } as AuthState),
    ).toBeUndefined();
    // The target's claims fail the app's claims schema (organization is o1).
    expect(await server.support.current(cookie, admin())).toBeUndefined();
    expect(server.support.sessionIdOf(cookie)).toBe(session.id);
    expect(server.support.clearCookie()).toContain("Max-Age=0");
    const anon = { kind: "anon", reason: "none" } as const;
    expect((await server.support.revoke(anon, session.id)).error?.kind).toBe(
      "unauthorized",
    );
    expect((await server.support.list(anon)).error?.kind).toBe("unauthorized");
    expect(await server.support.revoke(admin(), session.id).orThrow()).toBe(
      true,
    );
    expect(store.sessions.get(session.id)?.endedBy).toBe("revoked");
  });

  it("keeps the admin's own view when the store fails", async () => {
    const store = memorySupportStore();

    const { server } = setup({
      support: supportSessions({
        store: { ...store, get: () => Promise.reject(new Error("down")) },
      }),
    });

    const ctx = await server.context(await request("bs-support=x"));
    expect(ctx.support).toBeUndefined();
    expect(ctx.auth).toMatchObject({ user: { id: ADMIN } });
  });

  it("expires sessions past their expiry and reports each as ended", async () => {
    const { server, store, events } = setup();

    const started = await server.support
      .start(admin(), { targetUserId: TARGET, reason: "ticket 9" })
      .orThrow();

    expect(await server.support.expire().orThrow()).toEqual([]);
    store.sessions.set(started.session.id, {
      ...started.session,
      expiresAt: Temporal.Now.instant().subtract({ seconds: 1 }),
    });
    const expired = await server.support.expire().orThrow();
    expect(expired.map((session) => session.endedBy)).toEqual(["expired"]);
    expect(events.at(-1)).toMatchObject({
      type: "support.ended",
      actorId: ADMIN,
      subject: `support_sessions/${started.session.id}`,
      data: {
        sessionId: started.session.id,
        adminId: ADMIN,
        targetUserId: TARGET,
        reason: "ticket 9",
        endedBy: "expired",
      },
    });
  });

  it("serves expire as a cron route behind its secret", async () => {
    const { server, store } = setup();

    const started = await server.support
      .start(admin(), { targetUserId: TARGET, reason: "r" })
      .orThrow();

    store.sessions.set(started.session.id, {
      ...started.session,
      expiresAt: Temporal.Now.instant().subtract({ seconds: 1 }),
    });
    expect(() => server.support.expireRoute({ secret: undefined })).toThrow(
      /expireRoute needs a secret/,
    );
    const route = server.support.expireRoute({ secret: "s3cret" });
    const url = "https://app.test/api/cron/support";
    expect((await route(new Request(url))).status).toBe(401);

    const response = await route(
      new Request(url, { headers: { authorization: "Bearer s3cret" } }),
    );

    expect(await response.json()).toEqual({ expired: 1 });
  });

  it("fails expire for a store without it, and when the store fails", async () => {
    const withoutExpire = memorySupportStore();
    delete (withoutExpire as { expire?: unknown }).expire;

    const { server } = setup({
      support: supportSessions({ store: withoutExpire }),
    });

    expect((await server.support.expire()).error).toMatchObject({
      kind: "unsupported",
      code: "SUPPORT_EXPIRE_UNSUPPORTED",
    });
    const route = server.support.expireRoute({ secret: "s" });

    const response = await route(
      new Request("https://app.test/cron", {
        method: "POST",
        headers: { authorization: "Bearer s" },
      }),
    );

    expect(response.status).toBe(501);

    const failing = setup({
      support: supportSessions({
        store: {
          ...memorySupportStore(),
          expire: () => Promise.reject(pgError("57014", "timeout")),
        },
      }),
    });

    expect((await failing.server.support.expire()).error?.kind).toBe("timeout");
  });

  it("fails expire without support options", async () => {
    const server = createServer(defineSupabase(schema), { env });
    expect((await server.support.expire()).ok).toBe(false);

    const response = await server.support.expireRoute({ secret: "s" })(
      new Request("https://app.test/cron"),
    );

    expect(response.status).toBe(500);
  });

  it("passes the definition's temporal on to the store", () => {
    const store = memorySupportStore();
    const withTemporal = vi.fn(() => store);
    createServer(defineSupabase(schema, { temporal: Temporal }), {
      env,
      postgres: fakePostgres().postgres,
      support: supportSessions({ store: { ...store, withTemporal } }),
    });
    expect(withTemporal).toHaveBeenCalledWith(Temporal);
  });

  it("reads Storage as the target in a support session", async () => {
    const { server, pg } = setup(
      { env: { ...env, secretKey: "sb_secret_test" } },
      [["as visible", [{ visible: false }]]],
    );

    const normal = await server.context(await request());
    expect(normal.storage).toBeUndefined();

    const started = await server.support
      .start(admin(), { targetUserId: TARGET, reason: "ticket 9" })
      .orThrow();

    const ctx = await server.context(
      await request(`bs-support=${started.session.id}`),
    );

    const docs = ctx.storage!.from("docs");
    expect(ctx.storage).toBe(ctx.storage);
    expect(ctx.db.$storage).toBe(ctx.storage);
    expect(ctx.sql?.$storage).toBe(ctx.storage);
    expect((await docs.download("o1/a.pdf")).error).toMatchObject({
      code: "NoSuchKey",
    });
    expect((await docs.upload("o1/a.pdf", "x")).error?.code).toBe(
      "SUPPORT_READ_ONLY",
    );
    expect(pg.claims.at(-1)).toMatchObject({
      sub: TARGET,
      act: { kind: "support", session_id: started.session.id },
    });
    expect(pg.sessions.at(-1)).toMatchObject({ readOnly: true });
    expect(pg.fake.calls.at(-1)?.values).toEqual(["docs", "o1/a.pdf"]);
  });

  it("writes Storage as the target in a writable support session", async () => {
    const { server, pg } = setup(
      {
        env: { ...env, secretKey: "sb_secret_test" },
        support: supportSessions({
          store: memorySupportStore({
            [TARGET]: { role: "authenticated", organization: "o1" },
          }),
          policy: { readOnly: "default" },
        }),
      },
      [
        [
          "insert into storage.objects",
          { throws: pgError("42501", "new row violates row-level security") },
        ],
      ],
    );

    const started = await server.support
      .start(admin(), { targetUserId: TARGET, reason: "fix", readOnly: false })
      .orThrow();

    const ctx = await server.context(
      await request(`bs-support=${started.session.id}`),
    );

    const docs = ctx.storage!.from("docs");
    expect((await docs.upload("o1/a.pdf", "x")).error).toMatchObject({
      status: 403,
      code: "AccessDenied",
    });
    expect(pg.fake.transactions).toBeGreaterThan(0);
    expect(pg.fake.texts().slice(-3)).toEqual([
      "savepoint better_supabase_support_write",
      expect.stringContaining("insert into storage.objects"),
      "rollback to savepoint better_supabase_support_write",
    ]);
    expect(pg.fake.calls.at(-2)?.values).toEqual([
      "docs",
      "o1/a.pdf",
      TARGET,
      TARGET,
      JSON.stringify({
        supportSessionId: started.session.id,
        supportAdminId: ADMIN,
      }),
    ]);
    expect(pg.sessions.at(-1)).not.toMatchObject({ readOnly: true });
    expect(await docs.createSignedUploadUrl("o1/b.pdf")).toMatchObject({
      data: null,
      error: { status: 403, code: "AccessDenied" },
    });
    expect(pg.fake.calls.at(-2)?.values.slice(0, 2)).toEqual([
      "docs",
      "o1/b.pdf",
    ]);
  });
});
