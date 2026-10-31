import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { renderBlocks } from "../../src/sql/render.ts";

const OWN = {
  "public.my_counts": "supabase/schemas/a.sql",
  "public.my_count_lines": "supabase/schemas/a.sql",
  "public.my_rules": "supabase/schemas/a.sql",
  "public.my_groups": "supabase/schemas/a.sql",
  "public.my_group_parties": "supabase/schemas/a.sql",
  "public.my_intrastat": "supabase/schemas/a.sql",
};

const ADOPTED: BlockSqlLayout = {
  modules: {
    inventory: {
      tables: {
        counts: "public.my_counts",
        countLines: "public.my_count_lines",
      },
    },
    catalog: {
      tables: {
        discountRules: "public.my_rules",
        discountGroups: "public.my_groups",
        discountGroupParties: "public.my_group_parties",
      },
    },
    shipments: { tables: { intrastatLines: "public.my_intrastat" } },
  },
  ownTables: OWN,
};

const render = (
  layout: BlockSqlLayout,
  names = ["catalog", "inventory", "shipments"],
): string =>
  renderBlocks(names, layout)
    .map((file) => file.contents)
    .join("\n");

describe("discounts, counts and Intrastat over the app's tables", () => {
  const sql = render(ADOPTED);

  it("keeps the functions and adds only the columns the tables lack", () => {
    for (const fn of [
      "resolve_line_discount",
      "post_stock_count",
      "prepare_intrastat",
    ]) {
      expect(sql).toContain(fn);
    }

    expect(sql).toContain('alter table "public"."my_rules" add column');
    expect(sql).not.toContain('create table if not exists "public"."my_rules"');
    expect(sql).not.toContain(
      'create table if not exists "better_supabase"."discount_rules"',
    );
    expect(sql).not.toContain(
      'create table if not exists "better_supabase"."stock_counts"',
    );
  });

  it("manages the tables the app did not map", () => {
    const partial = render(
      {
        modules: { catalog: { tables: { discountRules: "public.my_rules" } } },
        ownTables: { "public.my_rules": OWN["public.my_rules"] },
      },
      ["catalog"],
    );

    expect(partial).toContain(
      'create table if not exists "better_supabase"."discount_groups"',
    );
  });
});

describe("discounts, counts and Intrastat switched off", () => {
  it("renders none of them when the tables map to null", () => {
    const sql = render({
      modules: {
        inventory: { tables: { counts: null, countLines: null } },
        catalog: {
          tables: {
            discountRules: null,
            discountGroups: null,
            discountGroupParties: null,
          },
        },
        shipments: { tables: { intrastatLines: null } },
      },
    });

    for (const name of [
      "resolve_line_discount",
      "post_stock_count",
      "prepare_intrastat",
      "discount_rules",
      "stock_counts",
      "intrastat_lines",
    ]) {
      expect(sql).not.toContain(name);
    }
  });
});

describe("variant columns the app leaves out", () => {
  it("falls back to null for the group and trade code", () => {
    const sql = render({
      modules: {
        catalog: {
          columns: { variants: { discountGroup: null, tradeCode: null } },
        },
      },
    });

    expect(sql).toContain("resolve_line_discount");
    expect(sql).toContain("null::uuid");
    expect(sql).not.toContain("set_variant_discount_group");
  });
});
