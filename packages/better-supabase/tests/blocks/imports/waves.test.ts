import { describe, expect, it } from "vitest";

import { importWaves } from "../../../src/blocks/imports/waves.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

describe("import waves", () => {
  it("puts an independent entity beside the first and the dependent one after", () => {
    expect(
      importWaves([
        { entity: "invoice", dependsOn: ["party"] },
        { entity: "party" },
        { entity: "contact_method" },
      ]),
    ).toEqual([["party", "contact_method"], ["invoice"]]);
  });

  it("refuses a cycle", () => {
    expect(() =>
      importWaves([
        { entity: "a", dependsOn: ["b"] },
        { entity: "b", dependsOn: ["a"] },
      ]),
    ).toThrow(/cycle/);
  });

  it("refuses a batch whose earlier wave still has open chunks", () => {
    const sql = renderBlocks(["imports"])
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("IMPORT_DEPENDENCY_OPEN");
    expect(sql).toContain("unordered");
  });
});
