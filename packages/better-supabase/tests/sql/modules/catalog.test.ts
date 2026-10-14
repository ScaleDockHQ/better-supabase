import { describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../../src/sql/module-types.ts";

import { ISO_4217_MINOR_UNITS } from "../../../src/blocks/commerce/index.ts";
import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (layout: ModuleLayout = {}, names = ["catalog"]): string =>
  renderModules(names, layout)
    .filter((file) => file.module === "catalog")
    .map((file) => file.contents)
    .join("\n");

describe("catalog module", () => {
  it("stores money as bigint minor units next to a currency code", () => {
    const sql = sqlOf();
    expect(sql).toContain(`"amount" bigint not null check ("amount" >= 0)`);
    expect(sql).toContain(
      `"currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$')`,
    );
    expect(sql).toContain(`'amount', v_amount::text`);
  });

  it("checks currencies against the pinned ISO 4217 list", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      'create or replace function "better_supabase"."currency_minor_units"(code text)',
    );
    expect(sql).toContain(`('JPY', ${String(ISO_4217_MINOR_UNITS["JPY"])})`);
    expect(sql).toContain(`('KWD', 3)`);
  });

  it("enforces its own status transitions without a state machine", () => {
    expect(sqlOf()).toContain("CATALOG_TRANSITION_INVALID");
  });

  it("leaves transitions to a state machine on the products table", () => {
    const sql = sqlOf(
      {
        modules: {
          "state-machine": {
            options: {
              machines: {
                product_status: {
                  table: "better_supabase.products",
                  column: "status",
                  initial: "draft",
                  transitions: {
                    draft: ["active", "review"],
                    review: ["active"],
                    active: ["archived"],
                    archived: [],
                  },
                },
              },
            },
          },
        },
      },
      ["catalog", "state-machine"],
    );
    expect(sql).not.toContain("CATALOG_TRANSITION_INVALID");
    expect(sql).toContain("A state-machine machine owns the transitions");
  });

  it("adds anon storefront policies only when the storefront is public", () => {
    expect(sqlOf()).not.toContain("to anon, authenticated\nusing");
    expect(sqlOf()).toContain("drop policy if exists products_storefront");
    const open = sqlOf({
      modules: { catalog: { options: { storefront: "public" } } },
    });
    expect(open).toContain(
      `create policy products_storefront on "better_supabase"."products" for select to anon, authenticated`,
    );
    expect(open).toContain(
      `grant select on "better_supabase"."product_prices" to anon;`,
    );
    expect(open).toContain(`"price_list_id" is null and "variant_id" in`);
  });

  it("rejects an unknown storefront option", () => {
    expect(() =>
      sqlOf({ modules: { catalog: { options: { storefront: "open" } } } }),
    ).toThrow(/storefront must be "public" or "private"/);
  });

  it("leaves out the functions of tables an adopted catalog lacks", () => {
    const sql = sqlOf({
      modules: {
        catalog: {
          mode: "adopt",
          tables: {
            products: "public.products",
            variants: "public.variants",
            prices: "public.prices",
            options: null,
            optionValues: null,
            variantValues: null,
            priceLists: null,
            categories: null,
            productCategories: null,
            collections: null,
            collectionProducts: null,
            storefronts: null,
          },
          columns: {
            products: { description: null, kind: null },
            variants: { title: null, barcode: null, weight: null },
            prices: {
              priceList: null,
              compareAt: null,
              validFrom: null,
              validUntil: null,
            },
          },
        },
      },
    });
    expect(sql).toContain(`update "public"."products" x`);
    expect(sql).not.toContain('create table if not exists "');
    expect(sql).not.toContain("save_product_option");
    expect(sql).not.toContain("save_category");
    expect(sql).not.toContain("publish_storefront");
    expect(sql).toContain("this catalog has no price lists");
    expect(sql).toContain("a product without options has one variant");
  });
});
