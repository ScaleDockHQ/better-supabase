import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("inventory level reads", () => {
  const sql = renderBlocks(["inventory"])
    .map((file) => file.contents)
    .join("\n");

  it("filters levels by the requested variants", () => {
    const body = sql.slice(sql.indexOf('"inventory_levels"'));

    expect(body).toContain("variant_ids");
    expect(body).toContain("= any (inventory_levels.variant_ids)");
    expect(sql).toContain("inventory_status_counts");
    expect(sql).toContain("list_inventory_movements");
    expect(sql).toContain("like 'stock.%'");
  });
});
