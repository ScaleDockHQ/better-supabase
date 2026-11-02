import { describe, expect, it } from "vitest";

import type { AppTablesConfig } from "../../src/config/types/app-tables.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { APP_TABLES_MODULE } from "../../src/sql/modules/app-tables.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const BLOCKS = ["memberships", "organizations", "updated-at"];

function schemaOf(
  names: readonly string[],
  layout: BlockSqlLayout,
): string | undefined {
  return renderBlocks(names, layout).find(
    (file) => file.module === APP_TABLES_MODULE && file.kind === "schema",
  )?.contents;
}

const NOTES: AppTablesConfig = {
  notes: {
    columns: {
      title: { type: "text", nullable: false },
      body: { type: "text" },
      views: { type: "integer" },
    },
    search: true,
  },
};

describe("appTables search", () => {
  it("indexes every text column when search is true", () => {
    const sql = schemaOf(BLOCKS, { appTables: NOTES });

    expect(sql).toContain("search_tsv");
    expect(sql).toContain("notes_search_tsv_idx");
  });

  it("indexes only the named columns", () => {
    const sql = schemaOf(BLOCKS, {
      appTables: {
        notes: { ...NOTES["notes"], search: { columns: ["title"] } },
      },
    });

    expect(sql).toContain("notes_search_tsv_idx");
  });

  it("refuses a named column the table lacks", () => {
    expect(() =>
      schemaOf(BLOCKS, {
        appTables: {
          notes: { ...NOTES["notes"], search: { columns: ["nope"] } },
        },
      }),
    ).toThrow(
      'tables.notes.search.columns names "nope", which is not a column of the table',
    );
  });

  it("refuses a table without a text column to index", () => {
    expect(() =>
      schemaOf(BLOCKS, {
        appTables: {
          counters: { columns: { total: { type: "integer" } }, search: true },
        },
      }),
    ).toThrow("tables.counters.search needs at least one text column to index");
  });
});

describe("appTables scope per table", () => {
  it("lets one table own its rows by user and another stay shared", () => {
    const sql = schemaOf(BLOCKS, {
      appTables: {
        drafts: { scope: "user", columns: { title: { type: "text" } } },
        shared: { scope: "none", columns: { title: { type: "text" } } },
        kept: { scope: "inherit", columns: { title: { type: "text" } } },
        plain: { columns: { title: { type: "text" } } },
      },
    });

    expect(sql).toContain("user_id");
    expect(sql).toContain("organization_id");
    expect(sql).toContain('"shared"');
  });

  it("uses the layout scope for a table that inherits it", () => {
    const sql = schemaOf(["updated-at"], {
      scope: "user",
      appTables: {
        kept: { scope: "inherit", columns: { title: { type: "text" } } },
      },
    });

    expect(sql).toContain("user_id");
    expect(sql).not.toContain("organization_id");
  });
});

describe("appTables references to a block", () => {
  it("references a block table that has an id", () => {
    const sql = schemaOf(["memberships", "organizations", "tags"], {
      appTables: {
        pins: {
          columns: {
            tag_id: {
              type: "uuid",
              references: { block: "tags", table: "tags", onDelete: "cascade" },
            },
          },
        },
      },
    });

    expect(sql).toContain("on delete cascade");
  });
});
