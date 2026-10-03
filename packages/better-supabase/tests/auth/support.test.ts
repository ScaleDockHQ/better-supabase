import { describe, expect, it } from "vitest";

import type { SqlClaims } from "../../src/postgres/pool.ts";

import { impersonatorOf } from "../../src/auth/impersonation.ts";
import {
  clearSupportCookie,
  sqlSupportStore,
  supportClaims,
  supportCookie,
  supportCookieValue,
  supportSessionFromRow,
} from "../../src/auth/support.ts";
import { supportOf, toSession } from "../../src/auth/view.ts";
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
  });
});

describe("supportClaims", () => {
  it("keeps the target's claims and names the admin in act", () => {
    const claims = supportClaims(
      { id: "s", adminId: "a", targetUserId: "t", reason: "r", readOnly: true },
      { sub: "ignored", role: "", org_roles: { o: "member" } },
    );
    expect(claims).toEqual({
      sub: "t",
      role: "authenticated",
      org_roles: { o: "member" },
      act: { sub: "a", reason: "r", session_id: "s", read_only: true },
    });
    expect(impersonatorOf(claims)).toEqual({
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
