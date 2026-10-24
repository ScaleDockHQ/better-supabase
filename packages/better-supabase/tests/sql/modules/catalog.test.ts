import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { ISO_4217_MINOR_UNITS } from "../../../src/commerce/index.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

const sqlOf = (layout: BlockSqlLayout = {}, names = ["catalog"]): string =>
  renderBlocks(names, layout)
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

  it("leaves out the functions of tables the app's catalog lacks", () => {
    const modules = {
      catalog: {
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
    };

    const sql = sqlOf({ modules, ownTables: ownTablesOf(modules) });

    expect(sql).toContain(`update "public"."products" x`);
    expect(sql).not.toContain('create table if not exists "public"');
    expect(sql).not.toContain("save_product_option");
    expect(sql).not.toContain("save_category");
    expect(sql).not.toContain("publish_storefront");
    expect(sql).toContain("this catalog has no price lists");
    expect(sql).toContain("a product without options has one variant");
    expect(sql).toContain(
      'create table if not exists "better_supabase"."catalog_channels"',
    );
    expect(sql).toContain("save_catalog_channel");
  });

  it("adds channels with listings and a price per channel", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."catalog_channels"',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."catalog_channel_products"',
    );
    expect(sql).toContain(
      'create or replace function "better_supabase"."save_catalog_channel"(tenant uuid, channel uuid, key text, name text, currency text, price_list uuid, active boolean)',
    );
    expect(sql).toContain(
      'create or replace function "better_supabase"."set_channel_listing"(channel uuid, products uuid[], listed boolean)',
    );
    expect(sql).toContain(
      'create or replace function "better_supabase"."channel_products"(channel uuid, locale text default null, page_size integer default null, after text default null)',
    );
    expect(sql).toContain(
      'create or replace function "better_supabase"."channel_price"(channel uuid, variant uuid, as_of timestamptz default null)',
    );
    expect(sql).toContain("CATALOG_CHANNEL_TAKEN");
  });

  it("keeps the variant_price signature quote lines rely on", () => {
    expect(sqlOf()).toContain(
      'create or replace function "better_supabase"."variant_price"(variant uuid, currency text, price_list uuid default null, as_of timestamptz default null)',
    );
  });

  it("translates product and variant text into the configured locales", () => {
    const sql = sqlOf({
      modules: { catalog: { options: { locales: ["en", "de", "pt-BR"] } } },
    });

    expect(sql).toContain(
      'create table if not exists "better_supabase"."product_translations"',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."product_variant_translations"',
    );
    expect(sql).toContain("'{en,de,pt-BR}'::text[]");
    expect(sql).toContain("CATALOG_LOCALE_DEFAULT");
    expect(sql).toContain("split_part(");
    expect(sql).toContain(
      'create or replace function "better_supabase"."product_text"(product uuid, locale text default null)',
    );
  });

  it("defaults to one English locale", () => {
    expect(sqlOf()).toContain("'{en}'::text[]");
  });

  it("rejects locales that are not language tags or repeat", () => {
    expect(() =>
      sqlOf({ modules: { catalog: { options: { locales: ["en_US"] } } } }),
    ).toThrow(/"en_US" is not a language tag/);
    expect(() =>
      sqlOf({ modules: { catalog: { options: { locales: ["en", "en"] } } } }),
    ).toThrow(/lists a locale twice/);
    expect(() =>
      sqlOf({ modules: { catalog: { options: { locales: [] } } } }),
    ).toThrow(/locales/);
  });

  it("adds product media only when attachments is installed", () => {
    expect(sqlOf()).not.toContain("product_media");

    const sql = sqlOf({}, ["catalog", "attachments"]);
    expect(sql).toContain(
      'create table if not exists "better_supabase"."product_media"',
    );
    expect(sql).toContain('references "better_supabase"."attachments"');
    expect(sql).toContain(
      'create or replace function "better_supabase"."add_product_media"',
    );
    expect(sql).toContain(
      'create or replace function "better_supabase"."reorder_product_media"(product uuid, media uuid[])',
    );
    expect(sql).toContain(
      'create or replace function "better_supabase"."remove_product_media"(media uuid)',
    );
    expect(sql).toContain("CATALOG_MEDIA_ATTACHMENT_NOT_FOUND");
  });

  it("opens the new tables to the storefront when it is public", () => {
    const open = sqlOf(
      { modules: { catalog: { options: { storefront: "public" } } } },
      ["catalog", "attachments"],
    );

    for (const table of [
      "catalog_channels",
      "catalog_channel_products",
      "product_translations",
      "product_variant_translations",
      "product_media",
    ]) {
      expect(open).toContain(`"better_supabase"."${table}" for select to anon`);
    }
  });
});
