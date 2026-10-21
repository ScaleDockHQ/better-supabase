import { describe, expect, it } from "vitest";

import {
  CATEGORY_NAMES,
  categoryHref,
  categoryStyle,
} from "../../../features/blocks/categories";
import { blockCategories } from "../../../lib/blocks";

describe("block categories", () => {
  it("every catalog category has a style, in catalog order", () => {
    expect(blockCategories).toEqual([...CATEGORY_NAMES]);

    for (const name of blockCategories) {
      expect(categoryStyle(name).name).toBe(name);
    }
  });

  it("slugs are unique and link to the blocks index", () => {
    const slugs = CATEGORY_NAMES.map((name) => categoryStyle(name).slug);
    expect(new Set(slugs).size).toBe(slugs.length);
    expect(categoryHref("CRM & sales")).toBe("/blocks#crm-sales");
  });

  it("an unknown category throws", () => {
    expect(() => categoryStyle("Nope")).toThrow(/Nope/u);
  });
});
