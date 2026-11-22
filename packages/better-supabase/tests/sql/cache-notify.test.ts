import { describe, expect, it } from "vitest";

import {
  CACHE_NOTIFY_BEARER_SECRET,
  CACHE_NOTIFY_URL_SECRET,
  cacheInvalidationSql,
} from "../../src/sql/cache-notify.ts";
import { schema } from "../fixtures/generated-camel.ts";

const meta = schema.meta;

describe("cacheInvalidationSql", () => {
  it("creates the function once and reads its settings from Vault", () => {
    const sql = cacheInvalidationSql(meta, { tables: ["notes"] });

    expect(sql.match(/create or replace function/gu)).toHaveLength(1);
    expect(sql).toContain("better_supabase.notify_cache()");
    expect(sql).toContain(`name = '${CACHE_NOTIFY_URL_SECRET}'`);
    expect(sql).toContain(`name = '${CACHE_NOTIFY_BEARER_SECRET}'`);
    expect(sql).toContain("security definer");
    expect(sql).toContain("set search_path = ''");
    expect(sql).toContain("net.http_post(");
  });

  it("adds statement triggers with transition tables for each event", () => {
    const sql = cacheInvalidationSql(meta, { tables: ["notes"] });

    expect(sql).toContain(
      'create trigger "bsb_cache_insert_notes" after insert on "public"."notes"',
    );
    expect(sql).toContain("referencing new table as new_rows");
    expect(sql).toContain(
      "referencing old table as old_rows new table as new_rows",
    );
    expect(sql).toContain("referencing old table as old_rows\n");
    expect(sql.match(/for each statement/gu)).toHaveLength(3);
  });

  it("passes database column names for the keys and the tenant", () => {
    const sql = cacheInvalidationSql(meta, {
      tables: ["customerTags"],
      maxRows: 50,
    });

    expect(sql).toContain(
      "notify_cache('customer_id,tag_id', 'organization_id', '50')",
    );
  });

  it("passes no tenant column for a table without one", () => {
    expect(cacheInvalidationSql(meta, { tables: ["plans"] })).toContain(
      "notify_cache('key', '', '1000')",
    );
  });

  it("covers every table and no view by default", () => {
    const sql = cacheInvalidationSql(meta);

    expect(sql).toContain('"public"."customers"');
    expect(sql).not.toContain('"public"."customers_with_owner"');
  });

  it("rejects a table the schema doesn't have", () => {
    expect(() => cacheInvalidationSql(meta, { tables: ["nope"] })).toThrow(
      "unknown table nope",
    );
  });
});
