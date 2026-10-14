import { describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../../src/sql/module-types.ts";

import { renderModules } from "../../../src/sql/render.ts";

const NAMES = ["catalog", "inventory"];

const sqlOf = (module: string, layout: ModuleLayout = {}): string =>
  renderModules(NAMES, layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("inventory module", () => {
  it("references catalog variants and derives available stock", () => {
    const sql = sqlOf("inventory");
    expect(sql).toContain(
      `references "better_supabase"."product_variants" ("id") on delete cascade`,
    );
    expect(sql).toContain(
      `"available" integer generated always as ("on_hand" - "reserved") stored`,
    );
  });

  it("keeps the movement ledger append-only and applies it with a trigger", () => {
    const sql = sqlOf("inventory");
    expect(sql).toContain("INVENTORY_LEDGER_APPEND_ONLY");
    expect(sql).toContain("apply_stock_movement");
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
      renderModules(["catalog"], {})
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
