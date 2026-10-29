import { describe, expect, it } from "vitest";

import { QUALIFICATIONS } from "../../../src/sql/modules/qualifications.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

const MODULES = ["memberships", "permissions"];

describe("qualifications module", () => {
  it("renders its tables and functions", () => {
    const sql = renderBlocks([...MODULES, "qualifications"])
      .filter(
        (file) => file.module === "qualifications" && file.kind === "schema",
      )
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain('"better_supabase"."qualification_types"');
    expect(sql).toContain('"better_supabase"."qualification_requirements"');
    expect(sql).toContain('"better_supabase"."qualifications"');
    expect(sql).toContain('"better_supabase"."grant_qualification"(');
    expect(sql).toContain('"better_supabase"."qualification_gaps"(');
  });

  it("renders nothing in custom mode", () => {
    const sql = renderBlocks([...MODULES, "qualifications"], {
      modules: { qualifications: { mode: "custom" } },
    })
      .filter((file) => file.module === "qualifications")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toBe("");
  });

  it("lists its functions in the contract", () => {
    expect(
      customContracts(["qualifications"], {
        modules: { qualifications: { mode: "custom" } },
      })[0]?.functions.map((fn) => fn.name),
    ).toEqual(QUALIFICATIONS.contract?.({} as never).map((fn) => fn.name));
  });
});
