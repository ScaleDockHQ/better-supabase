import { describe, expect, it } from "vitest";

import { ensureExclusion } from "../../src/sql/exclusion.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import {
  searchColumnStatements,
  SEARCH_COLUMN,
} from "../../src/sql/search-column.ts";

// The opt-in Postgres features of ADR 0198: a stored tsvector column, gist
// exclusion constraints and monthly partitions. Each block renders the same SQL
// as before until its option is on.

function render(module: string, options: Record<string, unknown>): string {
  return renderBlocks([module], { modules: { [module]: { options } } })
    .filter((file) => file.module === module)
    .map((file) => `-- ==== ${file.kind} ${file.path}\n${file.contents}`)
    .join("\n");
}

describe("searchColumnStatements", () => {
  it("generates a stored tsvector and a gin index", () => {
    const sql = searchColumnStatements(
      '"app"."notes"',
      "notes_search_tsv_idx",
      ['"title"', '"body"'],
    );

    expect(sql).toContain(
      `add column if not exists ${SEARCH_COLUMN} tsvector generated always as (to_tsvector('simple'::regconfig, coalesce("title", '') || ' ' || coalesce("body", ''))) stored`,
    );
    expect(sql).toContain(
      `create index if not exists "notes_search_tsv_idx" on "app"."notes" using gin (${SEARCH_COLUMN});`,
    );
  });

  it("renders nothing without columns", () => {
    expect(searchColumnStatements("t", "i", [])).toBe("");
  });
});

describe("ensureExclusion", () => {
  it("adds the constraint once, behind btree_gist", () => {
    const sql = ensureExclusion(
      '"app"."leases"',
      "leases_no_overlap",
      [
        { expression: '"unit_id"', operator: "=" },
        { expression: "daterange(a, b)", operator: "&&" },
      ],
      `"status" = 'active'`,
    );

    expect(sql).toContain("create extension if not exists btree_gist");
    expect(sql).toContain("if not exists (");
    expect(sql).toContain(
      `exclude using gist ("unit_id" with =, daterange(a, b) with &&) where ("status" = 'active')`,
    );
  });
});

describe.each([
  ["contacts", "companies"],
  ["deals", "deals"],
  ["tasks", "tasks"],
  ["invoices", "invoices"],
] as const)("%s searchColumn", (module, table) => {
  it("renders no search column by default", () => {
    expect(render(module, {})).not.toContain(SEARCH_COLUMN);
  });

  it("adds a generated column and a gin index", () => {
    const sql = render(module, { searchColumn: true });

    expect(sql).toContain(
      `add column if not exists ${SEARCH_COLUMN} tsvector generated always as`,
    );
    expect(sql).toContain(`${table}_search_tsv_idx`);
    expect(sql).toContain(`using gin (${SEARCH_COLUMN})`);
  });
});

describe("drive texts searchColumn", () => {
  it("indexes the first characters of the extracted text", () => {
    const sql = render("drive", { searchColumn: true });

    expect(sql).toContain("left(");
    expect(sql).toContain("using gin (search_tsv)");
    expect(render("drive", {})).not.toContain(SEARCH_COLUMN);
  });
});

describe("noOverlap", () => {
  it("keeps a unit's active leases apart", () => {
    const sql = render("leases", { noOverlap: true });

    expect(sql).toContain("exclude using gist");
    expect(sql).toContain("daterange(");
    expect(sql).toContain("'infinity'::date");
    expect(render("leases", {})).not.toContain("exclude using gist");
  });

  it("keeps a calendar's opaque timed events apart", () => {
    const sql = render("calendar", { noOverlap: true });

    expect(sql).toContain("calendar_events_no_overlap");
    expect(sql).toContain("tstzrange(");
    expect(render("calendar", {})).not.toContain("exclude using gist");
  });

  it("keeps a holder's active passes of a kind apart", () => {
    const sql = render("passes", { noOverlap: true });

    expect(sql).toContain("passes_no_overlap");
    expect(render("passes", {})).not.toContain("exclude using gist");
  });
});

describe("field-history partitioned", () => {
  it("partitions field_changes by changed_at", () => {
    const sql = render("field-history", { partitioned: true });

    expect(sql).toContain("partition by range");
    expect(sql).toContain("primary key");
    expect(sql).toContain("ensure_partitions");
    expect(sql).toContain("nextval(");
  });

  it("keeps the identity table by default", () => {
    const sql = render("field-history", {});

    expect(sql).toContain("generated always as identity primary key");
    expect(sql).not.toContain("partition by range");
  });
});
