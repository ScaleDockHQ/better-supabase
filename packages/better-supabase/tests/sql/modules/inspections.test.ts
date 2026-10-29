import { describe, expect, it } from "vitest";

import { INSPECTIONS } from "../../../src/sql/modules/inspections.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

const MODULES = ["memberships", "permissions"];

describe("inspections module", () => {
  it("renders its tables and functions", () => {
    const sql = renderBlocks([...MODULES, "inspections"])
      .filter((file) => file.module === "inspections" && file.kind === "schema")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain('"better_supabase"."inspection_programs"');
    expect(sql).toContain('"better_supabase"."inspections"');
    expect(sql).toContain('"better_supabase"."inspection_findings"');
    expect(sql).toContain('"better_supabase"."schedule_inspection"(');
    expect(sql).toContain('"better_supabase"."raise_inspection_finding_case"(');
  });

  it("renders nothing in custom mode", () => {
    const sql = renderBlocks([...MODULES, "inspections"], {
      modules: { inspections: { mode: "custom" } },
    })
      .filter((file) => file.module === "inspections")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toBe("");
  });

  it("lists its functions in the contract", () => {
    expect(
      customContracts(["inspections"], {
        modules: { inspections: { mode: "custom" } },
      })[0]?.functions.map((fn) => fn.name),
    ).toEqual(INSPECTIONS.contract?.({} as never).map((fn) => fn.name));
  });
});
