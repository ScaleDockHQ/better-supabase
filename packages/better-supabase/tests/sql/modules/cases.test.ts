import { describe, expect, it } from "vitest";

import { CASES } from "../../../src/sql/modules/cases.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

const MODULES = ["memberships", "permissions"];

describe("cases module", () => {
  it("renders its tables and functions", () => {
    const sql = renderBlocks([...MODULES, "cases"])
      .filter((file) => file.module === "cases" && file.kind === "schema")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain('"better_supabase"."case_kinds"');
    expect(sql).toContain('"better_supabase"."cases"');
    expect(sql).toContain('"better_supabase"."case_actions"');
    expect(sql).toContain('"better_supabase"."open_case"(');
    expect(sql).toContain('"better_supabase"."case_close_blockers"(');
    expect(sql).toContain('"better_supabase"."close_case"(');
  });

  it("renders nothing in custom mode", () => {
    const sql = renderBlocks([...MODULES, "cases"], {
      modules: { cases: { mode: "custom" } },
    })
      .filter((file) => file.module === "cases")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toBe("");
  });

  it("lists its functions in the contract", () => {
    expect(
      customContracts(["cases"], { modules: { cases: { mode: "custom" } } })[0]
        ?.functions.map((fn) => fn.name),
    ).toEqual(CASES.contract?.({} as never).map((fn) => fn.name));
  });
});
