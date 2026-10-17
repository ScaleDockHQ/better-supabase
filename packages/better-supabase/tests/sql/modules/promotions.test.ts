import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (names: readonly string[]): string =>
  renderModules([...names], {})
    .filter((file) => file.module === "promotions")
    .map((file) => file.contents)
    .join("\n");

const BASE = ["catalog", "orders", "promotions"];

describe("promotions module", () => {
  it("keeps pricing and redemption internal to orders", () => {
    const sql = sqlOf(BASE);
    for (const fn of [
      "cart_discounts",
      "redeem_promotions",
      "release_promotions",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `revoke execute on function "better_supabase"\\."${fn}"\\([^)]*\\) from public, anon, authenticated;`,
        ),
      );
      expect(sql).not.toMatch(
        new RegExp(`grant execute on function "better_supabase"\\."${fn}"\\(`),
      );
    }
    for (const fn of ["save_promotion", "apply_promotion_code"]) {
      expect(sql).toMatch(
        new RegExp(
          `grant execute on function "better_supabase"\\."${fn}"\\([^)]*\\) to authenticated`,
        ),
      );
    }
  });

  it("references the orders carts and the catalog targets", () => {
    const sql = sqlOf(BASE);
    expect(sql).toContain(`references "better_supabase"."carts"`);
    expect(sql).toContain(`references "better_supabase"."orders"`);
    expect(sql).toContain("scope is order, products, categories, collections");
    expect(sql).toContain("for update");
  });

  it("records promotion.redeemed only through the outbox", () => {
    expect(sqlOf(BASE)).not.toContain("'promotion.redeemed'");
    expect(sqlOf(["catalog", "outbox", "orders", "promotions"])).toContain(
      "'promotion.redeemed'",
    );
  });

  it("installs catalog and orders with it", () => {
    const modules = renderModules(["promotions"], {}).map(
      (file) => file.module,
    );
    expect(modules).toEqual(expect.arrayContaining(["catalog", "orders"]));
  });
});
