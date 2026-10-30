import { Pool } from "pg";
import { afterAll, afterEach, beforeEach, describe, expect, it } from "vitest";

import type { AppTablesConfig } from "../../src/config/types/app-tables.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

// Encrypted columns are ciphertext at rest and decrypt through
// `<table>_reveal`, which audits each call per tenant (ADR 0087). A lookup
// column keeps an HMAC of the value that `<table>_find` matches.
const TABLES: AppTablesConfig = {
  it_charts: {
    columns: {
      title: { type: "text", nullable: false },
      diagnosis: { type: "text", encrypted: true },
      dose: { type: "numeric", encrypted: true, min: 0 },
      bsn: { type: "text", format: "bsn", encrypted: true, lookup: true },
    },
    auditReads: true,
  },
};

const BLOCKS = [
  "memberships",
  "permissions",
  "organizations",
  "updated-at",
  "audit",
  "field-encryption",
  "custom-fields",
];

const LAYOUT: BlockSqlLayout = {
  appTables: TABLES,
  modules: { "custom-fields": { options: { auditReads: true } } },
};

describe.skipIf(!live)("field encryption", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  let s: BlockSession;
  let ann: TestUser;
  let annOrg: string;

  beforeEach(async () => {
    s = await BlockSession.open(pool);
    await s.install(BLOCKS, LAYOUT);
    ann = await s.user("ann");
    annOrg = await s.organization(ann);
  });

  afterEach(async () => {
    await s.close();
  });

  afterAll(async () => {
    await pool.end();
  });

  const charts = async (): Promise<string[]> => {
    await s.asRole(ann);

    for (const [title, diagnosis, dose] of [
      ["A", "asthma", "2.5"],
      ["B", "flu", "1"],
    ]) {
      await s.client.query(
        "insert into public.it_charts (organization_id, title, diagnosis, dose) values ($1, $2, $3, $4)",
        [annOrg, title, diagnosis, dose],
      );
    }

    await s.service();

    return (
      await s.rows<{ id: string }>(
        "select id::text from public.it_charts order by title",
      )
    ).map((row) => row.id);
  };

  it("stores ciphertext and reveals the configured type to a member", async () => {
    const ids = await charts();

    const stored = await s.rows<{ diagnosis: string; dose: string }>(
      "select diagnosis, dose from public.it_charts order by title",
    );

    expect(stored.every((row) => row.diagnosis.startsWith("bsf1:"))).toBe(true);
    expect(stored.every((row) => row.dose.startsWith("bsf1:"))).toBe(true);

    await s.asRole(ann);
    expect(await s.hint("select diagnosis from public.it_charts")).toMatch(
      /privileges/u,
    );

    const revealed = await s.rows<{ diagnosis: string; dose: string }>(
      "select diagnosis, dose::text from public.it_charts_reveal($1::uuid[]) order by diagnosis",
      [ids],
    );

    expect(revealed).toEqual([
      { diagnosis: "asthma", dose: "2.5" },
      { diagnosis: "flu", dose: "1" },
    ]);
  });

  it("writes one read entry per tenant and call, naming the rows", async () => {
    const ids = await charts();

    await s.asRole(ann);
    await s.client.query("select * from public.it_charts_reveal($1::uuid[])", [
      ids,
    ]);
    await s.client.query("select * from public.it_charts_reveal($1::uuid[])", [
      ids.slice(0, 1),
    ]);
    await s.service();

    const entries = await s.rows<{
      category: string;
      record_id: string | null;
      count: number;
    }>(
      `select category, record_id, jsonb_array_length(metadata -> 'ids') as count
       from better_supabase.audit_events
       where event_type = 'it_charts.viewed' and organization_id = $1 and actor_id = $2
       order by occurred_at, id`,
      [annOrg, ann.id],
    );

    expect(entries).toEqual([
      { category: "read", record_id: null, count: 2 },
      { category: "read", record_id: ids[0], count: 1 },
    ]);
  });

  it("reveals nothing outside the caller's scope and refuses anon and big batches", async () => {
    const ids = await charts();
    const bob = await s.user("bob");
    await s.organization(bob);

    await s.asRole(bob);
    expect(
      await s.value<number>(
        "(select count(*)::int from public.it_charts_reveal($1::uuid[]))",
        [ids],
      ),
    ).toBe(0);

    expect(
      await s.hint(
        "select * from public.it_charts_reveal(array(select gen_random_uuid() from generate_series(1, 501)))",
      ),
    ).toBe("APP_REVEAL_TOO_MANY");

    await s.asRole("anon");
    expect(
      await s.hint("select * from public.it_charts_reveal(array[]::uuid[])"),
    ).toMatch(/permission denied/u);
  });

  it("checks bounds before it seals and keeps ciphertext an update leaves alone", async () => {
    await charts();
    await s.asRole(ann);

    expect(
      await s.hint(
        "insert into public.it_charts (organization_id, title, dose) values ($1, 'C', '-1')",
        [annOrg],
      ),
    ).toMatch(/it_charts_dose_check/u);

    await s.service();

    const before = await s.value<string>(
      "(select diagnosis from public.it_charts where title = 'A')",
    );

    await s.client.query(
      "update public.it_charts set title = 'A2' where title = 'A'",
    );

    expect(
      await s.value<string>(
        "(select diagnosis from public.it_charts where title = 'A2')",
      ),
    ).toBe(before);
  });

  it("seals an upsert's values once and hashes its lookup again", async () => {
    const [id] = await charts();

    const upsert = `insert into public.it_charts (id, organization_id, title, diagnosis, bsn)
      values ($1, $2, 'A', $3, $4)
      on conflict (id) do update set diagnosis = excluded.diagnosis, bsn = excluded.bsn`;

    await s.client.query(upsert, [id, annOrg, "migraine", "111222333"]);
    await s.client.query(upsert, [id, annOrg, "sinusitis", "123456782"]);
    await s.asRole(ann);

    expect(
      await s.rows<{ diagnosis: string; bsn: string }>(
        "select diagnosis, bsn from public.it_charts_reveal(array[$1]::uuid[])",
        [id],
      ),
    ).toEqual([{ diagnosis: "sinusitis", bsn: "123456782" }]);
    expect(
      await s.rows<{ id: string }>(
        "select id::text from public.it_charts_find('bsn', '123456782')",
      ),
    ).toEqual([{ id }]);
    expect(
      await s.value<number>(
        "(select count(*)::int from public.it_charts_find('bsn', '111222333'))",
      ),
    ).toBe(0);
  });

  it("finds rows by an encrypted value's lookup, only in the caller's tenants", async () => {
    await s.asRole(ann);
    await s.client.query(
      "insert into public.it_charts (organization_id, title, bsn) values ($1, 'P', '111222333'), ($1, 'Q', '123456782')",
      [annOrg],
    );

    const found = await s.rows<{ title: string }>(
      "select c.title from public.it_charts_find('bsn', ' 111222333 ') f join public.it_charts c on c.id = f.id",
    );

    expect(found).toEqual([{ title: "P" }]);
    expect(
      await s.hint("select * from public.it_charts_find('dose', '1')"),
    ).toBe("APP_FIND_COLUMN");
    expect(
      await s.hint(
        "insert into public.it_charts (organization_id, title, bsn) values ($1, 'R', '123456789')",
        [annOrg],
      ),
    ).toMatch(/it_charts_bsn_check/u);

    await s.service();
    const bob = await s.user("bob");
    await s.organization(bob);
    await s.asRole(bob);
    expect(
      await s.value<number>(
        "(select count(*)::int from public.it_charts_find('bsn', '111222333'))",
      ),
    ).toBe(0);

    await s.service();

    const stored = await s.value<string>(
      "(select encode(bsn_lookup, 'hex') from public.it_charts where title = 'P')",
    );

    expect(
      await s.value<string>(
        "(select encode(better_supabase.field_lookup($1, '111222333'), 'hex'))",
        [`tenant:${annOrg}`],
      ),
    ).toBe(stored);

    await s.client.query(
      "update public.it_charts set bsn_lookup = '\\x00' where title = 'P'",
    );
    expect(
      await s.value<string>(
        "(select encode(bsn_lookup, 'hex') from public.it_charts where title = 'P')",
      ),
    ).toBe(stored);

    await s.client.query("select better_supabase.drop_field_key($1)", [
      `tenant:${annOrg}`,
    ]);
    expect(
      await s.value<number>(
        "(select count(*)::int from public.it_charts_find('bsn', '111222333'))",
      ),
    ).toBe(0);
  });

  it("checks identifier formats of custom field values", async () => {
    await s.asRole(ann);

    const definition = await s.value<string>(
      "(better_supabase.save_field_definition($1, 'contact', 'iban', 'IBAN', 'iban', false) ->> 'id')",
      [annOrg],
    );

    await s.client.query(
      "select better_supabase.set_field_value($1, 'contact', 'c-1', $2, 'NL91ABNA0417164300')",
      [annOrg, definition],
    );
    expect(
      await s.hint(
        "select better_supabase.set_field_value($1, 'contact', 'c-2', $2, 'NL91ABNA0417164301')",
        [annOrg, definition],
      ),
    ).toBe("FIELD_VALUE_INVALID");
  });

  it("encrypts a custom field's values, audits the read and shreds them with the key", async () => {
    await s.asRole(ann);

    const definition = await s.value<string>(
      "(better_supabase.save_field_definition($1, 'contact', 'notes', 'Notes', 'text', false) ->> 'id')",
      [annOrg],
    );

    await s.client.query(
      "select better_supabase.set_field_value($1, 'contact', 'c-1', $2, 'before')",
      [annOrg, definition],
    );
    await s.client.query(
      "select better_supabase.encrypt_field_definition($1)",
      [definition],
    );
    await s.client.query(
      "select better_supabase.set_field_value($1, 'contact', 'c-2', $2, 'after')",
      [annOrg, definition],
    );

    await s.service();
    expect(
      await s.value<boolean>(
        "(select bool_and(left(value_text, 5) = 'bsf1:') from better_supabase.field_values where definition_id = $1)",
        [definition],
      ),
    ).toBe(true);

    await s.asRole(ann);
    expect(
      await s.value<string>(
        "(better_supabase.read_field_values($1, 'contact', 'c-1') -> 0 ->> 'text')",
        [annOrg],
      ),
    ).toBe("before");

    await s.service();
    expect(
      await s.value<number>(
        "(select count(*)::int from better_supabase.audit_events where event_type = 'field_value.viewed' and category = 'read' and organization_id = $1)",
        [annOrg],
      ),
    ).toBe(1);

    await s.client.query("select better_supabase.drop_field_key($1)", [
      `tenant:${annOrg}`,
    ]);
    expect(
      await s.value<string | null>(
        "(better_supabase.read_field_values($1, 'contact', 'c-2') -> 0 ->> 'text')",
        [annOrg],
      ),
    ).toBeNull();
  });
});
