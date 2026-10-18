import { describe, expect, test } from "vitest";

import { BLOCK_ICONS, blockIcon } from "../../../features/blocks/block-icons";
import { categoryStyle } from "../../../features/blocks/categories";
import { blockCategories, blocks } from "../../../lib/blocks";

describe("block icons", () => {
  test("every catalog block has its own entry", () => {
    const missing = blocks
      .filter((block) => !Object.hasOwn(BLOCK_ICONS, block.name))
      .map((block) => block.name);

    expect(missing).toEqual([]);
  });

  test("no entry names a block the catalog lacks", () => {
    const names = new Set(blocks.map((block) => block.name));

    expect(Object.keys(BLOCK_ICONS).filter((name) => !names.has(name))).toEqual(
      [],
    );
  });

  test("blocks in the same category have different icons", () => {
    const shared = blockCategories.filter((category) => {
      const icons = blocks
        .filter((block) => block.category === category)
        .map((block) => blockIcon(block.name, category));

      return new Set(icons).size !== icons.length;
    });

    expect(shared).toEqual([]);
  });

  test("an unknown block falls back to its category icon", () => {
    expect(blockIcon("nope", "AI")).toBe(categoryStyle("AI").icon);
  });
});
