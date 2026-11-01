import { Temporal } from "temporal-polyfill";
import { describe, expect, it } from "vitest";

import { createQuotes } from "../../../src/blocks/quotes/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-15T09:00:00Z";

const ROW = {
  id: "q1",
  tenant_id: "o",
  number: "1",
  identifier: "Q-1",
  revision: 1,
  title: "Rollout",
  company_type: "company",
  company_id: "c1",
  contact_type: null,
  contact_id: null,
  owner_user_id: "u1",
  currency: "EUR",
  status: "draft",
  valid_until: "2026-11-14",
  terms: null,
  note: null,
  origin_type: "deal",
  origin_id: "d1",
  sent_at: null,
  viewed_at: null,
  decided_at: null,
  decided_by: null,
  decision_note: null,
  created_by: "u1",
  created_at: AT,
  updated_at: AT,
  list_total: "0",
  discount_total: "0",
  subtotal: "0",
  tax_total: "0",
  total: "0",
  lines: [],
  region: "eu",
};

const TOTALS = {
  listTotal: "5000",
  discountTotal: "0",
  subtotal: "5000",
  taxTotal: "0",
  total: "5000",
  currency: "EUR",
};

function setup() {
  const t = fieldsTransport({
    quote_from_deal: () => ROW,
    set_quote_lines: () => TOTALS,
    update_quote: () => ({ ...ROW, title: "Custom" }),
  });

  return { t, quotes: createQuotes({ transport: t }) };
}

describe("quotes helpers", () => {
  it("draftFromDeal alone is fromDeal", async () => {
    const { t, quotes } = setup();

    const quote = await quotes.draftFromDeal({ dealId: "d1" }).orThrow();

    expect(quote.id).toBe("q1");
    expect(t.calls.map(([fn]) => fn)).toEqual(["quote_from_deal"]);
  });

  it("draftFromDeal sets the lines and the header and returns the quote", async () => {
    const { t, quotes } = setup();

    const quote = await quotes
      .draftFromDeal({
        dealId: "d1",
        title: "Custom",
        validUntil: Temporal.PlainDate.from("2026-12-01"),
        lines: [{ description: "Setup", unitAmount: money(5000, "EUR") }],
      })
      .orThrow();

    expect(quote.title).toBe("Custom");
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "quote_from_deal",
      "set_quote_lines",
      "update_quote",
    ]);
  });

  it("draftFromDeal stops when the lines are refused", async () => {
    const t = fieldsTransport({ quote_from_deal: () => ROW });
    const quotes = createQuotes({ transport: t });

    const quote = await quotes.draftFromDeal({
      dealId: "d1",
      lines: [{ description: "Setup", unitAmount: money(5000, "EUR") }],
    });

    expect(quote.ok).toBe(false);
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "quote_from_deal",
      "set_quote_lines",
    ]);
  });
});
