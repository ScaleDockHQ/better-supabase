import { describe, expect, it } from "vitest";

import { preludeFile, preludeSql } from "../../../src/sql/pipeline/prelude.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const prelude = (names: readonly string[]) =>
  renderBlocks(names, {}).find((file) => file.module === "prelude");

describe("prelude", () => {
  it("renders no file without a schema module", () => {
    expect(preludeFile({}, [], [])).toBeUndefined();
    expect(prelude(["pgtap"])).toBeUndefined();
  });

  it("sorts before every module and has a block marker", () => {
    const file = prelude(["tasks"])!;

    expect(file.path).toBe(
      "supabase/schemas/900_better_supabase_000_prelude.sql",
    );
    expect(file.contents).toContain("-- @bsb-block prelude@1 managed");
  });

  it("defines each shared helper once, with no if not exists on the table", () => {
    const sql = prelude(["tasks"])!.contents;

    for (const name of [
      "actor_may_write",
      "raise_actor_readonly",
      "acting_member",
      "as_column_type",
      "try_column_type",
      "value_unsupported",
      "column_default",
      "import_run",
      "merge_subject_refs",
      "memo_get",
      "memo_set",
      "replace_equivalent_triggers",
    ]) {
      expect(
        sql.match(
          new RegExp(
            `create or replace function better_supabase\\.${name}\\(`,
            "g",
          ),
        ),
      ).toHaveLength(1);
    }

    expect(sql).toContain("create table better_supabase.blocks (");
    expect(sql).not.toContain("create table if not exists");
    expect(sql).not.toContain("\ndo $$");
  });

  it("defines the empty member set only when no memberships block installs and a file calls it", () => {
    const stub = "create function better_supabase.member_organization_ids(";

    const caller = {
      module: "x",
      kind: "schema",
      path: "x.sql",
      contents: "select better_supabase.member_organization_ids();",
    } as const;

    expect(preludeSql({}, ["x"], [caller])).toContain(stub);
    expect(
      preludeSql({}, ["x"], [{ ...caller, contents: "select 1;" }]),
    ).not.toContain(stub);
    expect(preludeSql({}, ["memberships", "x"], [caller])).not.toContain(stub);
  });

  it("keeps the function memberships defines when the render reruns", () => {
    const caller = {
      module: "x",
      kind: "schema",
      path: "x.sql",
      contents: "select better_supabase.member_organization_ids();",
    } as const;

    const sql = preludeSql({ rerunnable: true }, ["x"], [caller]);

    expect(sql).toContain(
      "if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then",
    );
    expect(sql).toContain(
      "create function better_supabase.member_organization_ids(",
    );
  });

  it("creates the blocks table only if it is missing when the render reruns", () => {
    const rerun = renderBlocks(["tasks"], { rerunnable: true }).find(
      (file) => file.module === "prelude",
    )!;

    expect(rerun.contents).toContain(
      "create table if not exists better_supabase.blocks (",
    );
    expect(prelude(["tasks"])!.contents).toContain(
      "create table better_supabase.blocks (",
    );
  });
});
