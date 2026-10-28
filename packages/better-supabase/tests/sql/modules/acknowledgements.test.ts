import { describe, expect, it } from "vitest";

import { ACKNOWLEDGEMENTS } from "../../../src/sql/modules/acknowledgements.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

const MODULES = ["memberships", "permissions", "subjects", "versions"];

function render(): string {
  return renderBlocks([...MODULES, "acknowledgements"])
    .filter((file) => file.module === "acknowledgements" && file.kind === "schema")
    .map((file) => file.contents)
    .join("\n");
}

describe("acknowledgements module", () => {
  it("renders its tables and functions", () => {
    const sql = render();

    expect(sql).toContain('"better_supabase"."acknowledgement_assignments"');
    expect(sql).toContain('"better_supabase"."acknowledgements"');
    expect(sql).toContain('"better_supabase"."assign_acknowledgement"(');
    expect(sql).toContain('"better_supabase"."acknowledge"(');
    expect(sql).toContain('"better_supabase"."acknowledgement_status"(');
    expect(sql).toContain('"better_supabase"."notify_due_acknowledgements"(');
  });

  it("renders nothing in custom mode", () => {
    const sql = renderBlocks([...MODULES, "acknowledgements"], {
      modules: { acknowledgements: { mode: "custom" } },
    })
      .filter((file) => file.module === "acknowledgements")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toBe("");
  });

  it("lists its functions in the contract", () => {
    expect(
      customContracts(["acknowledgements"], {
        modules: { acknowledgements: { mode: "custom" } },
      })[0]?.functions.map((fn) => fn.name),
    ).toEqual(ACKNOWLEDGEMENTS.contract?.({} as never).map((fn) => fn.name));
  });
});
