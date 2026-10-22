import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";

/**
 * The modules whose managed table takes `options.extraColumns`: the table that
 * gets the columns, and whether its reads build the row with
 * `jsonb_build_object` (and so return the columns under `fields`) or read the
 * whole row.
 */
const MODULES: readonly (readonly [
  module: string,
  table: string,
  read: "fields" | "row",
])[] = [
  ["share-links", "links", "fields"],
  ["signatures", "requests", "fields"],
  ["sla", "policies", "fields"],
  ["tags", "tags", "fields"],
  ["targets", "targets", "fields"],
  ["teams", "teams", "fields"],
  ["templates", "templates", "fields"],
  ["time-tracking", "entries", "fields"],
  ["trash", "items", "fields"],
  ["versions", "versions", "fields"],
  ["waitlist", "entries", "fields"],
  ["webhook-inbox", "messages", "fields"],
  ["work-items", "items", "row"],
  ["workflow-builder", "definitions", "fields"],
];

const sqlOf = (module: string, extraColumns: unknown): string =>
  renderBlocks([module], {
    modules: { [module]: { options: { extraColumns } } },
  })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("extraColumns on managed tables", () => {
  it.each(MODULES)(
    "%s adds, writes and reads the columns",
    (module, table, read) => {
      const name = SQL_MODULES[module]?.names?.tables[table]?.name;
      expect(name).toBeDefined();

      const sql = sqlOf(module, {
        app_note: "text",
        app_rank: "integer not null default 0",
      });

      expect(sql).toMatch(
        new RegExp(
          `alter table [^\\n]*"?${name}"? add column if not exists "app_note" text;`,
        ),
      );
      expect(sql).toContain(
        'add column if not exists "app_rank" integer not null default 0;',
      );
      expect(sql).toContain(`"app_note" = `);
      expect(sql).toContain('then r."app_note"');
      expect(sql.includes(`'fields', jsonb_build_object('app_note', `)).toBe(
        read === "fields",
      );
      expect(sqlOf(module, undefined)).not.toContain("app_note");
    },
  );

  it.each(MODULES)("%s refuses a column named fields", (module) => {
    expect(() => sqlOf(module, { fields: "jsonb" })).toThrow(/fields/);
  });

  it("takes fields on the functions that write a positional row", () => {
    const sql = sqlOf("tags", { app_note: "text" });
    expect(sql).toContain(
      'create_tag"(tenant uuid, kind text, name text, color text, description text, fields jsonb default null)',
    );
    expect(sql).toContain(
      'drop function if exists "better_supabase"."create_tag"(uuid, text, text, text, text);',
    );
    expect(sqlOf("tags", undefined)).toContain(
      'drop function if exists "better_supabase"."create_tag"(uuid, text, text, text, text, jsonb);',
    );
  });

  it("keeps the extra columns of a waitlist entry out of a repeated join", () => {
    expect(sqlOf("waitlist", { company: "text" })).toMatch(
      /where x\."id" = v_row\."id" and x\."created_at" = now\(\)/,
    );
  });

  it("leaves the extra columns out of a version read with a share token", () => {
    const sql = sqlOf("versions", { note: "text" });
    const shared = sql.slice(sql.indexOf("get_shared_version"));
    expect(shared.slice(0, shared.indexOf("$$;"))).not.toContain("'fields'");
  });
});
