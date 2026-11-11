import { describe, expect, it } from "vitest";

import { renderTagBlock } from "../../src/sql/tag-statements.ts";

const tag = (
  name: string,
  args: Record<string, string | true>,
): { name: string; args: Record<string, string | true> } => ({ name, args });

describe("list tag defaults and edges", () => {
  it("renders a list with no tenant, no search and the default sort", () => {
    const sql = renderTagBlock(
      "list",
      "public",
      "scale_items",
      tag("list", { tenant: "false" }),
    );

    expect(sql).toContain("filters jsonb default '{}'::jsonb");
    expect(sql).not.toContain("v_search");
    expect(sql).not.toContain("trgm_idx");
    expect(sql).toContain('"created_at" desc');
  });

  it("keeps an id sort as the only key and refuses a bad direction", () => {
    const sql = renderTagBlock(
      "list",
      "public",
      "scale_items",
      tag("list", { sort: "id:desc", search: "title" }),
    );

    expect(sql).toContain("v_search text");
    expect(sql).toContain("trgm_idx");
    expect(() =>
      renderTagBlock(
        "list",
        "public",
        "scale_items",
        tag("list", { sort: "created_at:sideways" }),
      ),
    ).toThrow(/use asc or desc/u);
  });
});

describe("idempotency tag", () => {
  it("indexes the column alone without a tenant, and takes a custom name", () => {
    const sql = renderTagBlock(
      "idempotency",
      "public",
      "scale_items",
      tag("idempotency", { tenant: "false", column: "request_key" }),
    );

    expect(sql).toContain('("request_key") where "request_key" is not null');
  });
});

describe("copy tag suffixes", () => {
  it("refuses a suffix on a column that is not copied", () => {
    expect(() =>
      renderTagBlock(
        "copy",
        "public",
        "scale_tasks",
        tag("copy", { columns: "title", suffix: "other: (copy)" }),
      ),
    ).toThrow(/not in columns/u);
  });

  it("copies without a suffix", () => {
    const sql = renderTagBlock(
      "copy",
      "public",
      "scale_tasks",
      tag("copy", { columns: "title,notes" }),
    );

    expect(sql).toContain('x."title"');
    expect(sql).not.toContain("||");
  });
});
