import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";

const NEEDS = ["organizations", "approvals"] as const;

const COLUMNS = [
  { name: "app_note", type: "text" },
  { name: "app_rank", type: "integer default 0" },
];

const sqlOf = (appColumns: boolean): string =>
  renderBlocks([...NEEDS], {
    ...(appColumns
      ? { appColumns: { "better_supabase.approval_items": COLUMNS } }
      : {}),
  })
    .filter((file) => file.module === "approvals")
    .map((file) => file.contents)
    .join("\n");

describe("extra columns on approval items (ADR 0585)", () => {
  it("returns the app's columns under fields and writes them from each item", () => {
    const plain = sqlOf(false);
    const sql = sqlOf(true);

    expect(plain).toContain("approval_items");
    expect(plain).not.toContain("app_note");
    expect(sql).toContain(
      `'fields', jsonb_build_object('app_note', x."app_note", 'app_rank', x."app_rank")`,
    );
    expect(sql).toContain(
      `jsonb_populate_record(null::"better_supabase"."approval_items", `,
    );
    expect(sql).toContain(`e.value -> 'fields'`);
  });
});
