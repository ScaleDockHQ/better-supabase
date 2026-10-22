import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const body = (
  module: string,
  layout: Parameters<typeof renderBlocks>[1] = {},
  extra: readonly string[] = [],
): string =>
  renderBlocks([module, ...extra], layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("quotes module", () => {
  it("opens the public link to anon and keeps the token hash out of reads", () => {
    const sql = body("quotes");
    expect(sql).toContain(
      'grant execute on function "better_supabase"."public_quote"(text) to anon, authenticated, service_role;',
    );
    expect(sql).toContain("- 'token_hash'");
    expect(sql).toContain("current_date + 30");
    expect(sql).not.toContain("quote_from_deal");
  });

  it("quotes deals and links them when deals and relations are installed", () => {
    const sql = body("quotes", {}, ["deals", "relations"]);
    expect(sql).toContain("quote_from_deal");
    expect(sql).toContain("'created_from'");
    expect(
      body("quotes", { modules: { quotes: { options: { validDays: 14 } } } }),
    ).toContain("current_date + 14");
  });

  it("rejects a bad validity and renders nothing in custom mode", () => {
    expect(() =>
      body("quotes", { modules: { quotes: { options: { validDays: 0 } } } }),
    ).toThrow(/validDays/);
    expect(
      body("quotes", { modules: { quotes: { mode: "custom" } } }),
    ).not.toContain("create_quote");
  });
});

describe("invoices module", () => {
  it("numbers invoices and credit notes apart, with numbering when configured", () => {
    const sql = body("invoices");
    expect(sql).toContain("'INV-' || v_seq::text");
    expect(sql).toContain("'CN-' || v_seq::text");
    expect(sql).not.toContain("invoice_from_quote");

    const numbered = body(
      "invoices",
      {
        modules: {
          numbering: {
            options: {
              entities: { invoice: { period: "year", format: "{yyyy}-{n}" } },
            },
          },
        },
      },
      ["numbering"],
    );

    expect(numbered).toContain("format_assigned_number('{yyyy}-{n}'");
  });

  it("invoices accepted quotes when quotes is installed", () => {
    expect(body("invoices", {}, ["quotes"])).toContain("invoice_from_quote");
  });

  it("rejects bad terms and renders nothing in custom mode", () => {
    expect(() =>
      body("invoices", {
        modules: { invoices: { options: { termsDays: -1 } } },
      }),
    ).toThrow(/termsDays/);
    expect(
      body("invoices", { modules: { invoices: { mode: "custom" } } }),
    ).not.toContain("issue_invoice");
  });
});
