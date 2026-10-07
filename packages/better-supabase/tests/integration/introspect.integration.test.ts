import { afterAll, describe, expect, it } from "vitest";

import { readExtras } from "../../src/cli/introspect/extras.ts";
import { catalogFingerprint } from "../../src/cli/introspect/fingerprint.ts";
import { openPg } from "../fixtures/pg.ts";

const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

const source = await openPg(dbUrl);

describe.skipIf(!source)("readExtras against the local stack", () => {
  const db = source!.queryable;

  afterAll(async () => {
    await source!.close();
  });

  it("keeps INCLUDE columns out of uniques and reads grants as any role", async () => {
    await db.query("begin");
    try {
      await db.query(`
        create schema introspect_probe;
        create table introspect_probe.items (id int primary key, code text, label text);
        create unique index items_code_idx on introspect_probe.items (code) include (label);
        grant select on introspect_probe.items to anon;
        create role introspect_probe_reader;
        grant usage on schema storage to introspect_probe_reader;
        grant select on storage.buckets to introspect_probe_reader;
        grant introspect_probe_reader to current_user;
        set local role introspect_probe_reader;
      `);
      const extras = await readExtras(db, ["introspect_probe"]);
      const items = extras.tables.find((table) => table.name === "items");

      expect(items?.uniques).toEqual([
        { name: "items_code_idx", columns: ["code"] },
      ]);
      expect(
        items?.indexes.find((index) => index.name === "items_code_idx")
          ?.columns,
      ).toEqual(["code"]);
      expect(items?.grants).toContainEqual({
        role: "anon",
        privileges: ["SELECT"],
      });
    } finally {
      await db.query("rollback");
    }
  });

  it("keeps the fingerprint across temporary tables", async () => {
    const before = await catalogFingerprint(db);
    await db.query("begin");
    try {
      await db.query(
        "create temp table introspect_scratch (id int primary key, note text default 'x')",
      );
      expect(await catalogFingerprint(db)).toBe(before);
      await db.query("create table public.introspect_probe (id int)");
      expect(await catalogFingerprint(db)).not.toBe(before);
    } finally {
      await db.query("rollback");
    }
  });
});
