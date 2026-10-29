import { describe, expect, it } from "vitest";

import { RISKS } from "../../../src/sql/modules/risks.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

const MODULES = ["memberships", "permissions"];

describe("risks module", () => {
  it("renders its tables and functions", () => {
    const sql = renderBlocks([...MODULES, "risks"])
      .filter((file) => file.module === "risks" && file.kind === "schema")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain('"better_supabase"."risk_matrices"');
    expect(sql).toContain('"better_supabase"."risks"');
    expect(sql).toContain('"better_supabase"."risk_assessments"');
    expect(sql).toContain('"better_supabase"."assess_risk"(');
    expect(sql).toContain('"better_supabase"."risk_heatmap"(');
  });

  it("renders nothing in custom mode", () => {
    const sql = renderBlocks([...MODULES, "risks"], {
      modules: { risks: { mode: "custom" } },
    })
      .filter((file) => file.module === "risks")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toBe("");
  });

  it("lists its functions in the contract", () => {
    expect(
      customContracts(["risks"], { modules: { risks: { mode: "custom" } } })[0]
        ?.functions.map((fn) => fn.name),
    ).toEqual(RISKS.contract?.({} as never).map((fn) => fn.name));
  });
});
