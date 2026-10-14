import { describe, expect, it, vi } from "vitest";

import type { SqlClaims } from "../../src/postgres/pool.ts";

import { impersonatorOf } from "../../src/auth/impersonation.ts";
import {
  clearSupportCookie,
  supportCookie,
  supportCookieValue,
} from "../../src/auth/support-cookie.ts";
import { supportOf } from "../../src/auth/support-view.ts";
import {
  sqlSupportStore,
  supportClaims,
  supportSessionFromRow,
} from "../../src/auth/support.ts";
import { toSession } from "../../src/auth/view.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";

const ROW = {
  id: "11111111-1111-4111-8111-111111111111",
  admin_id: "a",
  target_user_id: "t",
  reason: "ticket 7",
  read_only: true,
  tenant: null,
  started_at: "2026-10-03T10:00:00Z",
  expires_at: "2026-10-03T10:30:00Z",
  ended_at: null,
  ended_by: null,
  metadata: { ticket: 7 },
};

describe("support cookies", () => {
  it("sets an HttpOnly cookie that lasts until the session expires", () => {
    const expiresAt = Temporal.Instant.from("2026-10-03T10:30:00Z");
    const now = Temporal.Instant.from("2026-10-03T10:00:00Z").epochMilliseconds;
    expect(supportCookie({ id: "s 1", expiresAt }, {}, now)).toBe(
      "bs-support=s%201; Path=/; Max-Age=1800; HttpOnly; SameSite=Lax; Secure",
    );
    expect(
      supportCookie({ id: "s", expiresAt }, { name: "sv", secure: false }, now),
    ).toBe("sv=s; Path=/; Max-Age=1800; HttpOnly; SameSite=Lax");
    expect(clearSupportCookie({ path: "/app" })).toBe(
      "bs-support=; Path=/app; Max-Age=0; HttpOnly; SameSite=Lax; Secure",
    );
  });

  it("reads the session id from a Cookie header", () => {
    expect(supportCookieValue("a=1; bs-support=s%201; b=2")).toBe("s 1");
    expect(supportCookieValue("sv=x", "sv")).toBe("x");
    expect(supportCookieValue("bs-support=")).toBeUndefined();
    expect(supportCookieValue("other=1")).toBeUndefined();
    expect(supportCookieValue(null)).toBeUndefined();
    expect(supportCookieValue("bs-support=%E0%A4%A")).toBeUndefined();
  });
});

describe("supportClaims", () => {
  it("keeps the target's claims and names the admin in act", () => {
    const claims = supportClaims(
      { id: "s", adminId: "a", targetUserId: "t", reason: "r", readOnly: true },
      { sub: "ignored", role: "", organization_roles: { o: "member" } },
    );
    expect(claims).toEqual({
      sub: "t",
      role: "authenticated",
      organization_roles: { o: "member" },
      act: {
        kind: "support",
        sub: "a",
        reason: "r",
        session_id: "s",
        read_only: true,
      },
    });
    expect(impersonatorOf(claims)).toEqual({
      kind: "support",
      id: "a",
      reason: "r",
      sessionId: "s",
      readOnly: true,
    });
  });

  it("shows the session through supportOf", () => {
    const claims = supportClaims(
      { id: "s", adminId: "a", targetUserId: "t", reason: "", readOnly: false },
      { role: "authenticated" },
    );
    const session = toSession({
      kind: "user",
      token: "",
      claims: claims as never,
      user: { id: "t" },
      source: "support",
      expiresAt: 100,
    });
    expect(supportOf(session)).toEqual({
      sessionId: "s",
      adminId: "a",
      targetUserId: "t",
      readOnly: false,
      expiresAt: 100,
    });
    expect(supportOf({ kind: "anon", reason: "none" })).toBeUndefined();
  });
});

describe("sqlSupportStore", () => {
  it("maps the module's jsonb to sessions", () => {
    const session = supportSessionFromRow({
      ...ROW,
      tenant: 42,
      read_only: null,
      ended_at: "2026-10-03T10:10:00Z",
      ended_by: "revoked",
      metadata: null,
    });
    expect(session).toMatchObject({
      tenant: "42",
      readOnly: true,
      endedBy: "revoked",
      metadata: {},
    });
    expect(session.endedAt?.toString()).toBe("2026-10-03T10:10:00Z");
  });

  it("starts as the admin and reads on the admin connection", async () => {
    const fake = fakeSql([
      ["start_support_session", [{ session: ROW }]],
      ["active_support_session", [{ session: null }]],
      ["end_support_session", [{ ended: true }]],
      ["list_support_sessions", [{ session: ROW }]],
      ["support_target_claims", [{ claims: { role: "authenticated" } }]],
    ]);
    const asUser: SqlClaims[] = [];
    const store = sqlSupportStore(
      {
        admin: fake.sql,
        asUser: (claims) => {
          asUser.push(claims);
          return fake.sql;
        },
      },
      { schema: "ops" },
    );
    const started = await store.start({
      adminId: "a",
      adminClaims: { sub: "a", role: "authenticated" },
      targetUserId: "t",
      reason: "ticket 7",
      ttlSeconds: 900,
      readOnly: true,
      metadata: { ticket: 7 },
    });
    expect(started.id).toBe(ROW.id);
    expect(asUser).toEqual([{ sub: "a", role: "authenticated" }]);
    expect(fake.calls[0]).toEqual({
      text: 'select "ops"."start_support_session"($1, $2, $3::interval, $4, $5, $6, $7) as session',
      values: ["t", "ticket 7", "900 seconds", true, '{"ticket":7}', null, "a"],
    });
    expect(await store.get(ROW.id, "a")).toBeUndefined();
    expect(await store.end(ROW.id, "revoked")).toBe(true);
    const listed = await store.list({ targetUserId: "t", active: true });
    expect(listed.map((session) => session.id)).toEqual([ROW.id]);
    expect(fake.calls.at(-1)?.values).toEqual([null, "t", true, 50]);
    expect(await store.claims!("t")).toEqual({ role: "authenticated" });
  });

  it("expires sessions on the admin connection", async () => {
    const fake = fakeSql([
      [
        "expire_support_sessions",
        [
          {
            session: { ...ROW, ended_at: ROW.expires_at, ended_by: "expired" },
          },
        ],
      ],
    ]);
    const store = sqlSupportStore(
      {
        admin: fake.sql,
        asUser: () => {
          throw new Error("expire runs as the admin connection");
        },
      },
      { schema: "ops" },
    );
    const expired = await store.expire!();
    expect(expired).toMatchObject([{ id: ROW.id, endedBy: "expired" }]);
    expect(fake.calls).toEqual([
      {
        text: 'select session from "ops"."expire_support_sessions"() as session',
        values: [],
      },
    ]);
  });

  it("reads time values with its own temporal, else the one passed in", async () => {
    const fake = fakeSql([["list_support_sessions", [{ session: ROW }]]]);
    const postgres = { admin: fake.sql, asUser: () => fake.sql };
    const namespace = (tag: string) => {
      const from = vi.fn((value: string) => ({ tag, value }));
      // SAFETY: the store only calls Instant.from.
      return {
        from,
        temporal: { Instant: { from } } as unknown as typeof Temporal,
      };
    };
    const own = namespace("own");
    const passed = namespace("passed");
    const [session] = await sqlSupportStore(postgres, {
      temporal: own.temporal,
    }).withTemporal!(passed.temporal).list();
    expect(session?.startedAt).toEqual({ tag: "own", value: ROW.started_at });
    expect(passed.from).not.toHaveBeenCalled();
    const [fromServer] = await sqlSupportStore(postgres).withTemporal!(
      passed.temporal,
    ).list();
    expect(fromServer?.expiresAt).toEqual({
      tag: "passed",
      value: ROW.expires_at,
    });
  });

  it("asks and approves as the caller, and over the admin connection for the server", async () => {
    const REQUEST = {
      id: "r1",
      admin_id: "a",
      target_user_id: "t",
      reason: "ticket 7",
      read_only: true,
      tenant: 42,
      metadata: null,
      requested_at: "2026-10-03T10:00:00Z",
      expires_at: "2026-10-03T11:00:00Z",
      approved_by: "b",
      approved_at: "2026-10-03T10:05:00Z",
      session_id: "s1",
    };
    const rules: Parameters<typeof fakeSql>[0] = [
      ["request_support_session", [{ request: REQUEST }]],
      ["approve_support_request", [{ request: REQUEST }]],
      ["approved_support_request", [{ request: null }]],
      ["support_request", [{ request: REQUEST }]],
    ];
    const admin = fakeSql(rules);
    const caller = fakeSql(rules);
    const asUser: SqlClaims[] = [];
    const store = sqlSupportStore(
      {
        admin: admin.sql,
        asUser: (claims) => {
          asUser.push(claims);
          return caller.sql;
        },
      },
      { schema: "ops" },
    );
    const input = {
      adminId: "a",
      adminClaims: { sub: "a" },
      targetUserId: "t",
      reason: "ticket 7",
      readOnly: true,
      metadata: { ticket: 7 },
    };
    const asked = await store.request!(input);
    expect(asked).toMatchObject({
      id: "r1",
      tenant: "42",
      metadata: {},
      approvedBy: "b",
      sessionId: "s1",
    });
    expect(asked.approvedAt?.toString()).toBe("2026-10-03T10:05:00Z");
    expect(caller.calls[0]).toEqual({
      text: 'select "ops"."request_support_session"($1, $2, $3, $4, $5, $6, $7) as request',
      values: ["t", "ticket 7", true, '{"ticket":7}', null, "a", null],
    });
    await store.request!({ ...input, tenant: "o1", approvedBy: "b" });
    expect(admin.calls.at(-1)?.values).toEqual([
      "t",
      "ticket 7",
      true,
      '{"ticket":7}',
      "o1",
      "a",
      "b",
    ]);

    await store.approve!("r1", { id: "b", claims: { sub: "b" } });
    expect(caller.calls.at(-1)).toEqual({
      text: 'select "ops"."approve_support_request"($1, $2) as request',
      values: ["r1", "b"],
    });
    await store.approve!("r1", { id: "b" });
    expect(admin.calls.at(-1)?.text).toContain("approve_support_request");
    expect(asUser).toEqual([{ sub: "a" }, { sub: "b" }]);

    expect(await store.getRequest!("r1")).toMatchObject({ id: "r1" });
    expect(
      await store.approvedRequest!({
        adminId: "a",
        targetUserId: "t",
        readOnly: false,
      }),
    ).toBeUndefined();
    expect(admin.calls.at(-1)).toEqual({
      text: 'select "ops"."approved_support_request"($1, $2, $3, $4) as request',
      values: ["t", null, false, "a"],
    });
    expect(
      await store.approvedRequest!({
        adminId: "a",
        targetUserId: "t",
        tenant: "o1",
        readOnly: true,
      }),
    ).toBeUndefined();
  });

  it("maps an unapproved request and rejects empty results", async () => {
    const fake = fakeSql([
      [
        "support_request",
        [
          {
            request: {
              id: "r2",
              admin_id: "a",
              target_user_id: "t",
              reason: "r",
              read_only: false,
              tenant: null,
              metadata: { x: 1 },
              requested_at: "2026-10-03T10:00:00Z",
              expires_at: "2026-10-03T11:00:00Z",
              approved_by: null,
              approved_at: null,
              session_id: null,
            },
          },
        ],
      ],
    ]);
    const store = sqlSupportStore({ admin: fake.sql, asUser: () => fake.sql });
    const found = await store.getRequest!("r2");
    expect(found).toEqual({
      id: "r2",
      adminId: "a",
      targetUserId: "t",
      reason: "r",
      readOnly: false,
      metadata: { x: 1 },
      requestedAt: Temporal.Instant.from("2026-10-03T10:00:00Z"),
      expiresAt: Temporal.Instant.from("2026-10-03T11:00:00Z"),
    });
    const empty = sqlSupportStore({
      admin: fakeSql().sql,
      asUser: () => fakeSql().sql,
    });
    expect(await empty.getRequest!("r2")).toBeUndefined();
    await expect(
      empty.request!({
        adminId: "a",
        adminClaims: {},
        targetUserId: "t",
        reason: "r",
        readOnly: true,
        metadata: {},
      }),
    ).rejects.toThrow(/no request/);
    await expect(empty.approve!("r2", { id: "b" })).rejects.toThrow(
      /no request/,
    );
  });

  it("rejects when start returns nothing", async () => {
    const fake = fakeSql([["start_support_session", [{ session: null }]]]);
    const store = sqlSupportStore({ admin: fake.sql, asUser: () => fake.sql });
    await expect(
      store.start({
        adminId: "a",
        adminClaims: {},
        targetUserId: "t",
        reason: "r",
        ttlSeconds: 60,
        readOnly: true,
        metadata: {},
      }),
    ).rejects.toThrow(/no session/);
  });
});
