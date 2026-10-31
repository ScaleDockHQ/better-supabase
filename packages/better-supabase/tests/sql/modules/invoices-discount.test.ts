import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { invoiceDiscountMatrix } from "../../../src/sql/modules/invoices-discount.ts";

const context = (on: boolean): BlockSqlContext =>
  // SAFETY: the helper only reads `flag`
  ({ flag: () => on }) as unknown as BlockSqlContext;

describe("invoiceDiscountMatrix", () => {
  it("adds nothing while the option is off", () => {
    expect(invoiceDiscountMatrix(context(false), "t", "id", ["a"])).toEqual({});
  });

  it("prices for the company, else the contact, today", () => {
    const { discountMatrix } = invoiceDiscountMatrix(
      context(true),
      "t",
      '"id"',
      ['"company_id"', '"contact_id"'],
    );

    expect(discountMatrix?.party).toBe(
      '(select coalesce(x."company_id", x."contact_id") from t x where x."id" = v_parent)',
    );
    expect(discountMatrix?.on).toBe("current_date");
  });

  it("falls back to null without a party column", () => {
    const { discountMatrix } = invoiceDiscountMatrix(
      context(true),
      "t",
      "id",
      [],
    );

    expect(discountMatrix?.party).toContain("coalesce(null)");
  });
});
