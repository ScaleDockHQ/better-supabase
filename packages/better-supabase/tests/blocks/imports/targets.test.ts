import { describe, expect, it } from "vitest";

import { importTargetsOf } from "../../../src/blocks/imports/targets.ts";
import { BLOCK_MANIFESTS } from "../../../src/blocks/registry.ts";
import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

describe("importTargetsOf", () => {
  it("lists every entity with its block, sorted", () => {
    expect(
      importTargetsOf([
        { name: "b", importTarget: ["y", "x"] },
        { name: "a", importTarget: ["m"] },
        { name: "c" },
      ]),
    ).toEqual([
      { entity: "m", block: "a" },
      { entity: "x", block: "b" },
      { entity: "y", block: "b" },
    ]);
  });

  it("rejects an entity two blocks declare", () => {
    expect(() =>
      importTargetsOf([
        { name: "a", importTarget: ["x"] },
        { name: "b", importTarget: ["x"] },
      ]),
    ).toThrow(/declared by "a" and "b"/);
  });
});

describe("block manifests importTarget", () => {
  const declared = BLOCK_MANIFESTS.filter(
    (block) => (block.importTarget ?? []).length > 0,
  );

  it("is declared by exactly the blocks whose SQL contributes imports", () => {
    const contributing = BLOCK_MANIFESTS.filter((block) =>
      block.sql.some((name) => SQL_MODULES[name]?.contributes?.imports),
    ).map((block) => block.name);

    expect(declared.map((block) => block.name).toSorted()).toEqual(
      contributing.toSorted(),
    );
  });

  it("names entities the imports module dispatches to", () => {
    const sql = renderBlocks(
      ["imports", ...new Set(declared.flatMap((block) => block.sql))],
      {},
    )
      .filter((file) => file.module === "imports")
      .map((file) => file.contents)
      .join("\n");

    for (const entity of declared.flatMap(
      (block) => block.importTarget ?? [],
    )) {
      expect(sql).toContain(`'${entity}'`);
    }
  });

  it("never repeats an entity across blocks", () => {
    expect(() => importTargetsOf(BLOCK_MANIFESTS)).not.toThrow();
  });
});
