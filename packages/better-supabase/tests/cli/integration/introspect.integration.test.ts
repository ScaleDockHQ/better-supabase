import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { IntrospectionSource } from "../../../src/cli/introspect/source.ts";

import { catalogFingerprint } from "../../../src/cli/introspect/fingerprint.ts";
import { introspect } from "../../../src/cli/introspect/index.ts";
import { pgSource } from "../../../src/cli/introspect/source.ts";

const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

const SCHEMA = `bs_caps_${Date.now()}`;

async function open(): Promise<IntrospectionSource | undefined> {
  try {
    const source = await pgSource(dbUrl);
    await source.queryable.query("select 1");
    return source;
  } catch {
    return undefined;
  }
}

const source = await open();

describe.skipIf(!source)("introspect against the local stack", () => {
  const db = source!;

  beforeAll(async () => {
    await db.queryable.query(`
      create schema ${SCHEMA};
      create table ${SCHEMA}.events (id bigint primary key);
      create table ${SCHEMA}.settings (id bigint primary key);
      insert into ${SCHEMA}.events select generate_series(1, 10000);
      insert into ${SCHEMA}.settings values (1);
      analyze ${SCHEMA}.events;
      analyze ${SCHEMA}.settings;
    `);
  });

  afterAll(async () => {
    await db.queryable.query(`drop schema if exists ${SCHEMA} cascade`);
    await db.queryable.query(
      `drop role if exists ${SCHEMA}_member; drop role if exists ${SCHEMA}_group`,
    );
    await db.close();
  });

  const tableNamed = async (name: string) => {
    const snapshot = await introspect(db.queryable, [SCHEMA]);
    return snapshot.extras.tables.find((table) => table.name === name);
  };

  it("reads constraints, indexes and grants of partitions", async () => {
    await db.queryable.query(`
      create table ${SCHEMA}.readings (
        id bigint not null,
        at date not null,
        kind text not null check (kind in ('a', 'b')),
        primary key (id, at)
      ) partition by range (at);
      create table ${SCHEMA}.readings_2026 partition of ${SCHEMA}.readings
        for values from ('2026-01-01') to ('2027-01-01');
      grant select on ${SCHEMA}.readings_2026 to authenticated;
    `);
    const partition = await tableNamed("readings_2026");
    expect(partition?.primaryKey).toEqual(["id", "at"]);
    expect(partition?.checks.map((check) => check.definition)).toEqual([
      "CHECK ((kind = ANY (ARRAY['a'::text, 'b'::text])))",
    ]);
    expect(partition?.indexes.map((index) => index.name)).toEqual([
      "readings_2026_pkey",
    ]);
    expect(partition?.grants).toContainEqual({
      role: "authenticated",
      privileges: ["SELECT"],
    });
  });

  it("reads table and column grants to PUBLIC", async () => {
    await db.queryable.query(`
      create table ${SCHEMA}.open (id bigint primary key, note text);
      revoke all on ${SCHEMA}.open from anon, authenticated, service_role;
      grant select on ${SCHEMA}.open to public;
      grant update (note) on ${SCHEMA}.open to public;
    `);
    const open = await tableNamed("open");
    expect(open?.grants).toEqual([{ role: "PUBLIC", privileges: ["SELECT"] }]);
    expect(open?.columnGrants).toEqual([
      { column: "note", role: "PUBLIC", privileges: ["UPDATE"] },
    ]);
  });

  it("leaves out invalid indexes", async () => {
    await db.queryable.query(`
      create table ${SCHEMA}.codes (id bigint primary key, code text);
      insert into ${SCHEMA}.codes values (1, 'x'), (2, 'x');
    `);
    await expect(
      db.queryable.query(
        `create unique index concurrently codes_code_key on ${SCHEMA}.codes (code)`,
      ),
    ).rejects.toThrow("could not create unique index");
    const codes = await tableNamed("codes");
    expect(codes?.indexes.map((index) => index.name)).toEqual(["codes_pkey"]);
    expect(codes?.uniques).toEqual([]);
  });

  it("changes the catalog fingerprint when a role membership changes", async () => {
    await db.queryable.query(
      `create role ${SCHEMA}_group nologin; create role ${SCHEMA}_member nologin`,
    );
    const before = await catalogFingerprint(db.queryable);
    await db.queryable.query(`grant ${SCHEMA}_group to ${SCHEMA}_member`);
    expect(await catalogFingerprint(db.queryable)).not.toBe(before);
  });

  it("marks tables Postgres estimates at 10,000 rows or more as large", async () => {
    const snapshot = await introspect(db.queryable, [SCHEMA]);
    const flags = Object.fromEntries(
      snapshot.extras.tables.map((table) => [table.name, table.large]),
    );
    expect(flags).toEqual({ events: true, settings: undefined });
  });

  it("keeps the catalog fingerprint through ANALYZE and changes it on DDL", async () => {
    const before = await catalogFingerprint(db.queryable);
    await db.queryable.query(`analyze ${SCHEMA}.settings`);
    expect(await catalogFingerprint(db.queryable)).toBe(before);
    await db.queryable.query(
      `alter table ${SCHEMA}.settings add column note text`,
    );
    const altered = await catalogFingerprint(db.queryable);
    expect(altered).not.toBe(before);
    await db.queryable.query(
      `comment on column ${SCHEMA}.settings.note is 'A note'`,
    );
    expect(await catalogFingerprint(db.queryable)).not.toBe(altered);
  });
});
