import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type { KitEvent } from "../../src/core/kit-events.ts";
import type {
  BetterPostgres,
  SessionOptions,
  SqlClaims,
} from "../../src/postgres/pool.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { postgresExecutor } from "../../src/postgres/executor.ts";
import { createServer } from "../../src/server/server.ts";
import { supportSessions } from "../../src/server/support.ts";
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
const ADMIN = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const TARGET = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

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

const admin = (claims: Record<string, unknown> = {}): AuthState => ({
  kind: "user",
  token: "t",
  claims: { sub: ADMIN, role: "authenticated", ...claims },
  user: { id: ADMIN, role: "authenticated", email: "admin@acme.test" },
  source: "bearer",
  expiresAt: null,
});

function setup(options: Parameters<typeof createServer>[1] = {}) {
  const betterSupabase = defineSupabase(schema);
  const events: KitEvent[] = [];
  betterSupabase.events.on("kit", (event) => events.push(event));
  const store = memorySupportStore({
    [TARGET]: { role: "authenticated", email: "member@acme.test", org: "o1" },
  });
  const pg = fakePostgres();
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
    expect((await server.support.revoke("s")).ok).toBe(false);
    expect((await server.support.list()).ok).toBe(false);
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
      org: "o1",
      sub: TARGET,
      act: {
        sub: ADMIN,
        reason: "ticket 9",
        session_id: started.session.id,
        read_only: true,
      },
    });
    expect(pg.sessions[0]).toEqual({ readOnly: true });
    expect(ctx.stats().calls).toBe(2);
    expect(ctx.apply(new Response()).status).toBe(200);

    const listed = await server.support.list({ adminId: ADMIN }).orThrow();
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
      settings: { "better_supabase.tenant": "t1" },
    });
    expect(ctx.auth.kind === "user" && ctx.auth.claims["act"]).toMatchObject({
      read_only: false,
    });
  });

  it("ignores the cookie for another admin, a nested token or bad claims", async () => {
    const { server, store } = setup({
      auth: {
        jwks: signer.jwks as never,
        claims: v.object({ org: v.literal("o2") }),
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
    // The target's claims fail the app's claims schema (org is o1).
    expect(await server.support.current(cookie, admin())).toBeUndefined();
    expect(server.support.sessionIdOf(cookie)).toBe(session.id);
    expect(server.support.clearCookie()).toContain("Max-Age=0");
    expect(await server.support.revoke(session.id).orThrow()).toBe(true);
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
});
