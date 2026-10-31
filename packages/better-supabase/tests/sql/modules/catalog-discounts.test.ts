import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const render = (
  names: readonly string[],
  options?: Record<string, unknown>,
): string =>
  renderBlocks(
    [...names],
    options === undefined
      ? {}
      : ({ modules: { quotes: { options } } } satisfies BlockSqlLayout),
  )
    .map((file) => file.contents)
    .join("\n");

const moduleSql = (module: string, names: readonly string[]): string =>
  renderBlocks([...names])
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("catalog discount matrix", () => {
  const sql = moduleSql("catalog", ["catalog"]);

  it("declares groups, a party membership and the rule matrix", () => {
    expect(sql).toContain(
      'create table if not exists "better_supabase"."discount_groups"',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."discount_rules"',
    );
    expect(sql).toContain("CATALOG_DISCOUNT_RULE_INVALID");
  });

  it("resolves the most specific rule, then the quantity break and start date", () => {
    const resolver = sql.slice(sql.indexOf('"resolve_line_discount"'));

    expect(resolver).toMatch(/order by[\s\S]*"min_quantity" desc/);
    expect(resolver).toContain('"valid_from" desc');
    expect(resolver).toContain('"min_quantity" <=');
  });

  it("registers import targets for groups and rules", () => {
    expect(sql).toContain("import_discount_group");
    expect(sql).toContain("import_discount_rule");
  });
});

describe("discountMatrix option", () => {
  it("leaves quote lines unpriced by the matrix by default", () => {
    expect(render(["catalog", "quotes"])).not.toContain(
      'resolve_line_discount"(v_tenant',
    );
  });

  it("prices quote lines through the matrix when on", () => {
    expect(render(["catalog", "quotes"], { discountMatrix: true })).toContain(
      'resolve_line_discount"(v_tenant',
    );
  });
});
