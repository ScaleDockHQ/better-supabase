import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";
import { SEED_LABELS, SEED_LOCALES } from "../../src/sql/seed-labels.ts";

describe("seed labels", () => {
  it("has en, nl and de for every seeded label", () => {
    for (const label of SEED_LABELS) {
      for (const locale of SEED_LOCALES) {
        expect(label.locales[locale], `${label.key} ${locale}`).toBeTruthy();
      }
    }
  });

  it("seeds the English letterhead", () => {
    const sql = renderBlocks(["document-templates"])
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("Company no.");
    expect(sql).toContain("p_locale = any (array['en'])");
  });
});
