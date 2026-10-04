import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { sqlSupportStore, supportClaims } from "../../src/auth/support.ts";
import { createPostgres } from "../../src/postgres/pool.ts";
import { renderKit } from "../../src/sql/kit.ts";
import { testSupportSessionStore } from "../../src/testing/conformance.ts";
import { FIXTURE_TENANT_SQL } from "./fixture-tenant.ts";

const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

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
        ...renderKit(["support-sessions"], {}).map((file) => file.contents),
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
      "select actor_id::text, support_session_id::text from better_supabase.audit_log where id = $1",
      [row?.id],
    );
    expect(audited).toEqual({
      actor_id: MEMBER,
      support_session_id: session.id,
    });
    expect(await store.end(session.id, "admin")).toBe(true);
  });
});
