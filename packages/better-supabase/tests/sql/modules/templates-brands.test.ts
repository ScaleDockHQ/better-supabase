import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (modules: readonly string[], layout: Layout = {}): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "templates")
    .map((file) => file.contents)
    .join("\n");

const brand = (value: unknown): Layout => ({
  modules: { templates: { options: { brand: value } } },
});

describe("brand-scoped templates", () => {
  it("adds the brand scope, its column and template_brand", () => {
    const sql = sqlOf(
      ["templates"],
      brand({ table: "public.organizations", column: "brand" }),
    );

    expect(sql).toContain(
      `add column if not exists "brand" text check (length("brand") between 1 and 100)`,
    );
    expect(sql).toContain(`check ("scope" in ('tenant', 'brand', 'system'))`);
    expect(sql).toContain(
      `when 'brand' then "tenant_id" is null and "brand" is not null`,
    );
    expect(sql).toContain(
      `drop index if exists "better_supabase".templates_key_idx;`,
    );
    expect(sql).toContain(
      `templates_brand_key_idx on "better_supabase"."templates" ("tenant_id", "brand", "key")`,
    );
    expect(sql).toContain(
      `select b."brand"::text from "public"."organizations" b`,
    );
    expect(sql).toContain(`where b."id" = template_brand.tenant`);
    expect(sql).toContain(
      `x."scope" = 'brand' and x."brand" = "better_supabase"."template_brand"(`,
    );
    expect(sql).toContain("nullif(v_starter ->> 'brand', '')");
    expect(sql).toContain("when 'brand' then 1 else 2 end");
    expect(sql).not.toContain("TEMPLATE_BRAND_UNSUPPORTED");
  });

  it("takes the tenant column when the brand lives elsewhere", () => {
    const sql = sqlOf(
      ["templates"],
      brand({ table: "brands", column: "slug", tenant: "organization_id" }),
    );

    expect(sql).toContain(`from "public"."brands" b`);
    expect(sql).toContain(`where b."organization_id" = template_brand.tenant`);
  });

  it("refuses brand starters without the option", () => {
    expect(sqlOf(["templates"])).toContain("TEMPLATE_BRAND_UNSUPPORTED");
  });

  it.each([
    ["a string", "brand", "must be { table, column, tenant? }"],
    [
      "a bad table",
      { table: "a.b.c", column: "brand" },
      'must be "table" or "schema.table"',
    ],
    [
      "a bad column",
      { table: "orgs", column: "Brand" },
      "column must be a lowercase identifier",
    ],
    [
      "a bad tenant",
      { table: "orgs", column: "brand", tenant: 1 },
      "tenant must be a lowercase identifier",
    ],
  ])("rejects %s", (_, value, message) => {
    expect(() => sqlOf(["templates"], brand(value))).toThrow(message);
  });

  it("needs the brand column", () => {
    expect(() =>
      sqlOf(["templates"], {
        modules: {
          templates: {
            options: { brand: { table: "orgs", column: "brand" } },
            columns: { templates: { brand: null } },
          },
        },
      }),
    ).toThrow("needs the templates table's scope and brand columns");
  });
});
