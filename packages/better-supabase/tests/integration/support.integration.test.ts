import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { sqlSupportStore, supportClaims } from "../../src/auth/support.ts";
import { createPostgres } from "../../src/postgres/pool.ts";
import { renderModules } from "../../src/sql/render.ts";
import { testSupportSessionStore } from "../../src/testing/kits/support-session-store.ts";
import { FIXTURE_HELPERS_SQL, FIXTURE_TENANT_SQL } from "./fixture-tenant.ts";
import { stackDbUrl } from "./stack-env.ts";

const dbUrl = stackDbUrl();

async function reachable(): Promise<boolean> {
  const pool = new Pool({
    connectionString: dbUrl,
    max: 1,
    connectionTimeoutMillis: 1000,
  });

  try {
    await pool.query("select 1");

    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const live = await reachable();

const ADMIN = "00000000-0000-4000-8000-0000000000a1";
const MEMBER = "00000000-0000-4000-8000-0000000000a2";
const OTHER = crypto.randomUUID();

const adminClaims = {
  sub: ADMIN,
  role: "authenticated",
  platform_permissions: ["support.*"],
};

describe.skipIf(!live)("support sessions against the local database", () => {
  const postgres = createPostgres({ connectionString: dbUrl, max: 4 });
  const store = sqlSupportStore(postgres);

  beforeAll(async () => {
    await postgres.admin.queryRaw(
      [
        // The second admin is covered in support-approval.integration.test.ts.
        ...renderModules(["support-sessions"], {
          modules: { "support-sessions": { options: { approval: "none" } } },
        }).map((file) => file.contents),
        FIXTURE_TENANT_SQL,
      ].join("\n;\n"),
    );
    await postgres.admin.queryRaw(
      `insert into auth.users (id, email, aud, role, instance_id)
       values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')`,
      [OTHER, `support-${OTHER}@example.test`],
    );
  });
  afterAll(async () => {
    await postgres.admin.queryRaw(
      "delete from better_supabase.support_sessions where admin_id = $1",
      [ADMIN],
    );
    await postgres.admin.queryRaw("delete from auth.users where id = $1", [
      OTHER,
    ]);
    await postgres.admin.queryRaw(FIXTURE_HELPERS_SQL);
    await postgres.end();
  });

  it("keeps the store contract", async () => {
    const report = await testSupportSessionStore(store, {
      admin: { id: ADMIN, claims: adminClaims },
      targets: [MEMBER, OTHER],
    });

    expect(report.checks.filter((check) => !check.ok)).toEqual([]);
  });

  it("refuses an admin without the platform permission", async () => {
    await expect(
      store.start({
        adminId: MEMBER,
        adminClaims: { sub: MEMBER, role: "authenticated" },
        targetUserId: OTHER,
        reason: "ticket 1",
        ttlSeconds: 600,
        readOnly: true,
        metadata: {},
      }),
    ).rejects.toMatchObject({ code: "42501" });
  });

  it("runs the target's queries read-only and audits them with the session", async () => {
    const session = await store.start({
      adminId: ADMIN,
      adminClaims,
      targetUserId: MEMBER,
      reason: "ticket 2",
      ttlSeconds: 600,
      readOnly: true,
      metadata: {},
    });

    const target = await store.claims?.(MEMBER);
    const claims = supportClaims(session, target ?? {});
    const asTarget = postgres.asUser(claims, { readOnly: true });

    const [who] = await asTarget.queryRaw<{ uid: string }>(
      "select auth.uid()::text as uid",
    );

    expect(who?.uid).toBe(MEMBER);
    await expect(
      asTarget.queryRaw(
        "insert into public.tags (organization_id, name, color) values ($1, 'support', 'gray')",
        ["00000000-0000-4000-8000-000000000001"],
      ),
    ).rejects.toMatchObject({ code: "25006" });

    const [row] = await postgres.admin.transaction!(async (tx) => {
      await tx.queryRaw("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify(claims),
      ]);

      return tx.queryRaw<{ id: string }>(
        "select better_supabase.audit_event('support.viewed') as id",
      );
    });

    const [audited] = await postgres.admin.queryRaw<{
      actor_id: string;
      support_session_id: string;
    }>(
      "select actor_id::text, support_session_id::text from better_supabase.audit_events where id = $1",
      [row?.id],
    );

    expect(audited).toEqual({
      actor_id: MEMBER,
      support_session_id: session.id,
    });
    expect(await store.end(session.id, "admin")).toBe(true);
  });

  it("refuses platform targets and writes, and checks every caller again", async () => {
    const start = (targetUserId: string, readOnly = true) =>
      store.start({
        adminId: ADMIN,
        adminClaims,
        targetUserId,
        reason: "ticket 3",
        ttlSeconds: 600,
        readOnly,
        metadata: {},
      });

    const member = { sub: MEMBER, role: "authenticated" };
    await postgres.admin.queryRaw(
      `update auth.users set raw_app_meta_data = coalesce(raw_app_meta_data, '{}') || '{"platform_permissions": ["support.view"]}' where id = $1`,
      [OTHER],
    );
    await expect(start(OTHER)).rejects.toMatchObject({
      hint: "SUPPORT_TARGET_PLATFORM",
    });
    await postgres.admin.queryRaw(
      "update auth.users set raw_app_meta_data = raw_app_meta_data - 'platform_permissions' where id = $1",
      [OTHER],
    );
    await expect(start(MEMBER, false)).rejects.toMatchObject({
      hint: "SUPPORT_WRITES_DISABLED",
    });

    const session = await start(MEMBER);
    expect(
      await store.get(session.id, ADMIN, { sub: ADMIN, role: "authenticated" }),
    ).toBeUndefined();
    expect(await store.get(session.id, ADMIN, adminClaims)).toMatchObject({
      id: session.id,
    });
    expect(await store.list({}, member)).toEqual([]);
    expect(await store.end(session.id, "revoked", member)).toBe(false);
    expect(await store.end(session.id, "expired", adminClaims)).toBe(true);

    const [ended] = await postgres.admin.queryRaw<{ ended_by: string }>(
      "select ended_by from better_supabase.support_sessions where id = $1",
      [session.id],
    );

    expect(ended?.ended_by).toBe("admin");
  });

  it("records the session in the impersonation columns and expires it", async () => {
    const session = await store.start({
      adminId: ADMIN,
      adminClaims,
      targetUserId: MEMBER,
      reason: "ticket 4",
      ttlSeconds: 600,
      readOnly: true,
      metadata: {},
    });

    const columns = (type: string) =>
      postgres.admin.queryRaw<{
        actor_id: string;
        support_session_id: string;
        impersonated_by: string;
        impersonation_reason: string;
      }>(
        `select actor_id::text, support_session_id::text, impersonated_by::text, impersonation_reason
         from better_supabase.audit_events
         where event_type = $1 and metadata ->> 'session_id' = $2`,
        [type, session.id],
      );

    expect(await columns("support.started")).toEqual([
      {
        actor_id: ADMIN,
        support_session_id: session.id,
        impersonated_by: ADMIN,
        impersonation_reason: "ticket 4",
      },
    ]);
    expect(
      (await store.expire!()).every((ended) => ended.id !== session.id),
    ).toBe(true);
    await postgres.admin.queryRaw(
      `update better_supabase.support_sessions
       set started_at = now() - interval '2 minutes', expires_at = now() - interval '1 minute'
       where id = $1`,
      [session.id],
    );
    const expired = await store.expire!();
    expect(expired.find((ended) => ended.id === session.id)).toMatchObject({
      endedBy: "expired",
    });
    expect(await store.get(session.id, ADMIN)).toBeUndefined();
    expect(await columns("support.ended")).toEqual([
      {
        actor_id: ADMIN,
        support_session_id: session.id,
        impersonated_by: ADMIN,
        impersonation_reason: "ticket 4",
      },
    ]);
    await expect(
      postgres
        .asUser(adminClaims)
        .queryRaw("select better_supabase.expire_support_sessions()"),
    ).rejects.toMatchObject({ code: "42501" });
  });
});
