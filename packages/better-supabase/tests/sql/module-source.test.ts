import { describe, expect, it } from "vitest";

import { moduleSource } from "../../src/sql/registry.ts";
import { writtenValuesOf } from "../helpers/facts.ts";

describe("moduleSource", () => {
  const layout = {
    modules: { employees: {}, leave: { options: { owner: "employee" } } },
  };

  it("renders a block that needs another installed block", () => {
    expect(moduleSource("leave", layout, ["employees", "leave"])).toContain(
      "create table",
    );
  });

  it("rejects the same block when the other block is not installed", () => {
    expect(() => moduleSource("leave", layout, ["leave"])).toThrow(
      "needs the employees block",
    );
  });

  it("returns undefined for an unknown block", () => {
    expect(moduleSource("nope")).toBeUndefined();
  });

  it("finds the statuses the cases block writes through its trigger", async () => {
    const sql = moduleSource("cases", { modules: { cases: {} } }, ["cases"]);

    expect(
      await writtenValuesOf(sql ?? "", "better_supabase.cases", "status"),
    ).toEqual(expect.arrayContaining(["closed", "canceled", "open"]));
  });
});
