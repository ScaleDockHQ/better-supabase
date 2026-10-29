import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const HOLDS: BlockSqlLayout = {
  modules: { quotes: { options: { holds: true } } },
};

const sqlOf = (
  names: readonly string[],
  module: string,
  layout: BlockSqlLayout = {},
): string =>
  renderBlocks([...names], layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("quotes options.holds", () => {
  it("allocates a sent version's lines and releases them through a status trigger", () => {
    const sql = sqlOf(["catalog", "inventory", "quotes"], "quotes", HOLDS);

    expect(sql).toContain(
      `perform "better_supabase"."allocate_stock"(v_row."tenant_id", v_hold.variant, null, v_hold.quantity, 'quote_version', v_version::text, v_hold.id::text, true);`,
    );
    expect(sql).toContain(
      `create or replace function "better_supabase"."release_quote_holds"(quote uuid)`,
    );
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."release_quote_holds"\(uuid\) to service_role;/,
    );
    expect(sql).toContain(
      `after update of "status" on "better_supabase"."quotes"`,
    );
  });

  it("releases the quote's holds when an order is made from it", () => {
    expect(
      sqlOf(["catalog", "inventory", "quotes", "orders"], "orders", HOLDS),
    ).toContain(
      `perform "better_supabase"."release_quote_holds"(v_quote."id");`,
    );
    expect(
      sqlOf(["catalog", "inventory", "quotes", "orders"], "orders"),
    ).not.toContain("release_quote_holds");
  });

  it("renders nothing for holds by default", () => {
    expect(sqlOf(["catalog", "inventory", "quotes"], "quotes")).not.toContain(
      "release_quote_holds",
    );
  });

  it("needs the inventory block", () => {
    expect(() => sqlOf(["quotes"], "quotes", HOLDS)).toThrow(
      "blocks.quotes.options.holds needs the inventory block",
    );
  });
});
