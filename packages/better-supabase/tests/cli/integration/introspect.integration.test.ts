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
    await db.close();
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
