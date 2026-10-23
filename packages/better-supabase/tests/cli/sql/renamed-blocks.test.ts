import { describe, expect, it } from "vitest";

import {
  formerBlockPath,
  renamedBlocksIn,
  renamedBlocksSql,
  withCurrentBlockNames,
} from "../../../src/cli/sql/renamed-blocks.ts";

describe("renamedBlocksIn", () => {
  it("lists the renamed blocks the markers name, once each", () => {
    const text = [
      "-- @bsb-block work-items@3",
      "-- @bsb-block-data work-items",
      "-- @bs-module tenant@2",
      "-- @bsb-block comments@1",
    ].join("\n");

    expect(renamedBlocksIn(text)).toEqual([
      { from: "tenant", to: "memberships" },
      { from: "work-items", to: "tasks" },
    ]);
  });

  it("ignores a name that only starts like a renamed one", () => {
    expect(renamedBlocksIn("-- @bsb-block jobs-board@1")).toEqual([]);
  });
});

describe("withCurrentBlockNames", () => {
  it("rewrites the markers and leaves the SQL alone", () => {
    const text = "-- @bsb-block jobs@2\ncreate table jobs ();\n";

    expect(withCurrentBlockNames(text)).toBe(
      "-- @bsb-block queue@2\ncreate table jobs ();\n",
    );
  });
});

describe("formerBlockPath", () => {
  it("names the 0.14 file of a renamed block", () => {
    expect(formerBlockPath("supabase/schemas/900_tasks.sql", "tasks")).toBe(
      "supabase/schemas/900_work_items.sql",
    );
  });

  it("is undefined for a block that kept its name", () => {
    expect(
      formerBlockPath("supabase/schemas/900_comments.sql", "comments"),
    ).toBeUndefined();
  });
});

describe("renamedBlocksSql", () => {
  it("moves each row only while the new name is free", () => {
    const sql = renamedBlocksSql([{ from: "actor", to: "created-by" }]);

    expect(sql).toContain(
      "update better_supabase.blocks set name = 'created-by'",
    );
    expect(sql).toContain("where name = 'actor'");
    expect(sql).toContain("b.name = 'created-by'");
    expect(sql).toContain("to_regclass('better_supabase.blocks')");
  });
});
