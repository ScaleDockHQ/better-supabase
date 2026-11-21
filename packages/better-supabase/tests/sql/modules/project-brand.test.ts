import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const render = (
  blockBrand?: { table: string; column: string },
  brand?: { table: string; column: string },
): string =>
  renderBlocks(["templates"], {
    modules: { templates: brand === undefined ? {} : { options: { brand } } },
    ...(blockBrand === undefined ? {} : { blockBrand }),
  })
    .map((file) => file.contents)
    .join("\n");

describe("sql.brand", () => {
  it("is the brand source of a block that sets none", () => {
    expect(render({ table: "public.orgs", column: "brand_json" })).toContain(
      "brand_json",
    );
  });

  it("is overridden by the block's own brand", () => {
    const sql = render(
      { table: "public.orgs", column: "brand_json" },
      { table: "public.orgs", column: "theme_json" },
    );

    expect(sql).toContain("theme_json");
    expect(sql).not.toContain("brand_json");
  });

  it("renders no brand source without either", () => {
    expect(render()).not.toContain("brand_json");
  });
});
