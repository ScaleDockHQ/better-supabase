import { describe, expect, it } from "vitest";

import { PRESET_CATALOG } from "../../src/preset/catalog.generated.ts";
import { namedPreset } from "../../src/preset/presets.ts";
import { resolvePreset } from "../../src/preset/resolve.ts";
import { SQL_MODULES } from "../../src/sql/index.ts";

const base = namedPreset("crm");

describe("declared links", () => {
  it("names a block and an entity of that block for every target", () => {
    for (const block of PRESET_CATALOG.blocks) {
      for (const link of block.links ?? []) {
        const target = SQL_MODULES[link.target.block];

        expect(target, `${block.name}.${link.key}`).toBeDefined();
        expect(
          Object.keys(target?.names?.entities ?? {}),
          `${block.name}.${link.key}`,
        ).toContain(link.target.entity);
      }
    }
  });

  it("names a source entity of its own module", () => {
    for (const block of PRESET_CATALOG.blocks) {
      for (const link of block.links ?? []) {
        expect(
          Object.keys(SQL_MODULES[block.name]?.names?.entities ?? {}),
          `${block.name}.${link.key}`,
        ).toContain(link.source);
      }
    }
  });

  it("uses unique keys within a block", () => {
    for (const block of PRESET_CATALOG.blocks) {
      const keys = (block.links ?? []).map((link) => link.key);

      expect(new Set(keys).size).toBe(keys.length);
    }
  });

  it("adds relations when a selected pair declares a conversion", () => {
    const resolved = resolvePreset({ ...base, blocks: ["quotes", "orders"] });

    const relations = resolved.blocks.find((each) => each.name === "relations");

    expect(relations?.selected).toBe(false);
    expect(relations?.requiredBy).toContain("orders");
    expect(resolved.links.map((link) => link.key)).toContain("fromQuote");
  });

  it("leaves relations out when no declared link has both ends installed", () => {
    const resolved = resolvePreset({ ...base, blocks: ["orders"] });

    expect(resolved.blocks.map((each) => each.name)).not.toContain("relations");
  });
});
