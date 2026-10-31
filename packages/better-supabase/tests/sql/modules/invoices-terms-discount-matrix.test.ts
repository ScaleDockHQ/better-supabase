import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { lineMatrix } from "../../../src/sql/modules/invoices-terms.ts";

const context = (on: boolean): BlockSqlContext =>
  // SAFETY: the helper only reads `flag`
  ({ flag: () => on }) as unknown as BlockSqlContext;

const t = (table: string): string => `"s"."${table}"`;
const i = (column: string): string => `"${column}"`;

describe("lineMatrix", () => {
  it("adds no matrix while the option is off", () => {
    expect(
      lineMatrix(context(false), t, i, () => true).discountMatrix,
    ).toBeUndefined();
  });

  it("prices for the company, else the contact, today", () => {
    const { discountMatrix } = lineMatrix(context(true), t, i, () => true);

    expect(discountMatrix?.party).toBe(
      '(select coalesce(x."companyId", x."contactId") from "s"."invoices" x where x."id" = v_parent)',
    );
    expect(discountMatrix?.on).toBe("current_date");
  });

  it("falls back to null without a party column", () => {
    const { discountMatrix } = lineMatrix(context(true), t, i, () => false);

    expect(discountMatrix?.party).toContain("coalesce(null)");
  });
});
