import { afterAll, describe, expect, it } from "vitest";

import { readExtras } from "../../src/cli/introspect/extras.ts";
import { catalogFingerprint } from "../../src/cli/introspect/fingerprint.ts";
import { openPg } from "../fixtures/pg.ts";
import { stackDbUrl } from "./stack-env.ts";

const dbUrl = stackDbUrl();

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
    // Other integration files change the shared database, so a reading only
    // counts when the catalog was identical before and after it.
    for (let attempt = 0; attempt < 10; attempt += 1) {
      const before = await catalogFingerprint(db);
      await db.query("begin");

      let withTemp: string;
      let withTable: string;

      try {
        await db.query(
          "create temp table introspect_scratch (id int primary key, note text default 'x')",
        );

        withTemp = await catalogFingerprint(db);
        await db.query("create table public.introspect_probe (id int)");
        withTable = await catalogFingerprint(db);
      } finally {
        await db.query("rollback");
      }

      if ((await catalogFingerprint(db)) !== before) {
        continue;
      }

      expect(withTemp).toBe(before);
      expect(withTable).not.toBe(before);

      return;
    }

    throw new Error("the catalog kept changing under the fingerprint test");
  });
});
