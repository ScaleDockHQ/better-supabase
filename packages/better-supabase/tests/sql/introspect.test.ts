import { describe, expect, it } from "vitest";

import {
  moduleEventTriggers,
  moduleExtensions,
  moduleHidingColumns,
  moduleSchemaExtensions,
} from "../../src/sql/introspect.ts";

describe("moduleExtensions", () => {
  it("quotes each extension once and keeps its schema", () => {
    expect(
      moduleExtensions(
        [
          'create extension if not exists "pg_trgm" with schema "extensions";',
          "create extension if not exists PG_TRGM;",
          "create extension if not exists citext;",
        ].join("\n"),
      ),
    ).toBe(
      [
        'create extension if not exists "pg_trgm" with schema "extensions";',
        'create extension if not exists "citext";',
      ].join("\n"),
    );
  });

  it("returns nothing for a body without extensions", () => {
    expect(moduleExtensions("create table a ();")).toBe("");
  });
});

describe("moduleSchemaExtensions", () => {
  it("reads only schema files", () => {
    expect(
      moduleSchemaExtensions([
        { kind: "schema", contents: "create extension if not exists pgmq;" },
        { kind: "data", contents: "create extension if not exists citext;" },
      ] as never),
    ).toEqual([
      { name: "pgmq", statement: 'create extension if not exists "pgmq";' },
    ]);
  });
});

describe("moduleHidingColumns", () => {
  it("names the messaging soft-delete column after renames", () => {
    expect(
      moduleHidingColumns(["messaging"], {
        modules: {
          messaging: { columns: { messages: { deletedAt: "removed_at" } } },
        },
      }),
    ).toEqual(["better_supabase.messages.removed_at"]);
  });

  it("skips modules without hiding columns", () => {
    expect(moduleHidingColumns(["memberships"], { modules: {} })).toEqual([]);
  });
});

describe("moduleEventTriggers", () => {
  it("skips unknown modules and modules whose sql throws", () => {
    expect(
      moduleEventTriggers(["missing", "broken"], {
        broken: {
          get sql(): string {
            throw new Error("needs a layout");
          },
        },
      } as never),
    ).toEqual([]);
  });
});
