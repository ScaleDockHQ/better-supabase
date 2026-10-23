import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const NAMES = ["catalog", "inventory"];

const sqlOf = (module: string, layout: BlockSqlLayout = {}): string =>
  renderBlocks(NAMES, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("inventory module", () => {
  it("keeps stock at the assets locations when its own table is off", () => {
    const layout: BlockSqlLayout = {
      modules: { inventory: { tables: { locations: null } } },
    };

    const sql = renderBlocks(NAMES, layout)
      .filter((file) => file.module === "inventory")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("inventory_locations");
    expect(sql).toContain(
      `references "better_supabase"."asset_locations" ("id") on delete cascade`,
    );
    expect(sql).toContain(`("archived_at" is null)`);
    expect(sql).toContain(
      `"archived_at" = case when coalesce(set_location_active.active, true) then null`,
    );
    expect(
      renderBlocks(NAMES, layout).some((file) => file.module === "assets"),
    ).toBe(true);
  });

  it("references catalog variants and derives available stock", () => {
    const sql = sqlOf("inventory");
    expect(sql).toContain(
      `references "better_supabase"."product_variants" ("id") on delete cascade`,
    );
    expect(sql).toContain(
      `"available" integer generated always as ("on_hand" - "reserved") stored`,
    );
  });

  it("posts every stock movement to the ledger through move_stock", () => {
    const sql = sqlOf("inventory");
    expect(sql).toContain(
      `"better_supabase"."ledger_post"(move_stock.tenant, 'stock.' || move_stock.reason`,
    );
    expect(sql).not.toContain("stock_movements (");
    expect(sql).not.toContain("apply_stock_movement()");
  });

  it("lets only the service role expire reservations", () => {
    const sql = sqlOf("inventory");
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."expire_reservations"\([^)]*\) to service_role;/,
    );
    expect(sql).not.toMatch(
      /grant execute on function "better_supabase"\."expire_reservations"\([^)]*\) to authenticated/,
    );
  });

  it("makes catalog refuse to delete variants with stock history", () => {
    expect(sqlOf("catalog")).toContain("CATALOG_VARIANT_IN_USE");
    expect(
      renderBlocks(["catalog"], {})
        .map((file) => file.contents)
        .join("\n"),
    ).not.toContain("CATALOG_VARIANT_IN_USE");
  });

  it("leaves out transfers and purchase orders an adopted inventory lacks", () => {
    const sql = sqlOf("inventory", {
      modules: {
        inventory: {
          tables: {
            transfers: null,
            transferLines: null,
            purchaseOrders: null,
            purchaseOrderLines: null,
          },
        },
      },
    });

    expect(sql).toContain("reserve_stock");
    expect(sql).not.toContain("create_transfer");
    expect(sql).not.toContain("save_purchase_order");
    expect(sql).not.toContain("stock_transfers");
  });
});
