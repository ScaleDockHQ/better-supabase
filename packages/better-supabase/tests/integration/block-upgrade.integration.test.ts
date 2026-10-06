import { readdir, readFile } from "node:fs/promises";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { renderBlocks, upgradePlan } from "../../src/sql/blocks.ts";

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

const FIXTURES = new URL("../fixtures/block-0.4.0/", import.meta.url);
const MODULES = ["tenant", "audit", "invitations"];

describe.skipIf(!live)("upgrading block modules installed by 0.4.0", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  afterAll(() => pool.end());

  it("renames the 0.4.0 tables and columns and keeps rows, triggers and the old names", async () => {
    const client = await pool.connect();
    const table = `public.bs_upgrade_${crypto.randomUUID().slice(0, 8)}`;
    const organization = crypto.randomUUID();
    try {
      await client.query("begin");
      await client.query("drop schema if exists better_supabase cascade");
      for (const name of (await readdir(FIXTURES)).toSorted())
        await client.query(await readFile(new URL(name, FIXTURES), "utf8"));

      const { rows: users } = await client.query<{ id: string }>(
        "select id from auth.users order by created_at limit 1",
      );
      const user = users[0]!.id;
      await client.query(
        `create table ${table} (id uuid primary key default gen_random_uuid(), organization_id uuid, name text);
         select better_supabase.audit('${table}');`,
      );
      await client.query(
        `insert into ${table} (organization_id, name) values ($1, 'before')`,
        [organization],
      );
      await client.query(
        "insert into better_supabase.memberships (org_id, user_id, role) values ($1, $2, 'owner')",
        [organization, user],
      );
      await client.query(
        "insert into better_supabase.invitations (org_id, email, token_hash, expires_at) values ($1, 'new@acme.test', 'hash', now() + interval '1 day')",
        [organization],
      );

      const plans = upgradePlan(
        MODULES.map((module) => ({ module, version: 1 })),
      );
      expect(plans.map((plan) => plan.module).toSorted()).toEqual(
        MODULES.toSorted(),
      );
      for (const plan of plans)
        for (const step of plan.steps) await client.query(step.sql);
      for (const file of renderBlocks(MODULES))
        if (file.kind !== "test") await client.query(file.contents);

      await client.query(
        `insert into ${table} (organization_id, name) values ($1, 'after')`,
        [organization],
      );
      const { rows: events } = await client.query<{
        organization_id: string;
        occurred_at: Date;
        op: string;
      }>(
        "select organization_id, occurred_at, op from better_supabase.audit_events where table_name = $1 order by id",
        [table],
      );
      expect(events.map((event) => event.op)).toEqual(["insert", "insert"]);
      expect(
        events.every((event) => event.organization_id === organization),
      ).toBe(true);
      expect(events[0]!.occurred_at).toBeInstanceOf(Date);

      const { rows: legacy } = await client.query<{ org_id: string; at: Date }>(
        "select org_id, at from better_supabase.audit_log where table_name = $1",
        [table],
      );
      expect(legacy).toHaveLength(2);
      expect(legacy[0]!.org_id).toBe(organization);

      const { rows: names } = await client.query<Record<string, unknown>>(
        `select
           to_regprocedure('better_supabase.audit_row_change()') is not null as row_change,
           to_regclass('better_supabase.audit_events_record_idx') is not null as record_idx,
           to_regclass('better_supabase.audit_events_organization_idx') is not null as organization_idx,
           (select count(*)::int from better_supabase.memberships where organization_id = $1) as members,
           (select count(*)::int from better_supabase.invitations where organization_id = $1) as invitations`,
        [organization],
      );
      expect(names[0]).toEqual({
        row_change: true,
        record_idx: true,
        organization_idx: true,
        members: 1,
        invitations: 1,
      });
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});
