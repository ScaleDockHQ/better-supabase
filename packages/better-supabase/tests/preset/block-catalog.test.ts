import { describe, expect, it } from "vitest";

import { PRESET_CATALOG } from "../../src/preset/catalog.generated.ts";
import { BLOCK_CATALOG } from "../../src/preset/index.ts";

describe("BLOCK_CATALOG", () => {
  it("lists every module once with a description and a listed category", () => {
    expect(BLOCK_CATALOG.blocks.map((block) => block.name)).toEqual(
      PRESET_CATALOG.blocks.map((block) => block.name),
    );

    for (const block of BLOCK_CATALOG.blocks) {
      expect(block.description).not.toBe("");
      expect(BLOCK_CATALOG.categories).toContain(block.category);
    }
  });
});
