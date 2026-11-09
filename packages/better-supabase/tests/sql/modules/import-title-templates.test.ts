import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (
  modules: readonly string[],
  module: string,
  options: Record<string, Record<string, unknown>> = {},
): string =>
  renderBlocks([...modules], {
    modules: Object.fromEntries(
      Object.entries(options).map(([name, value]) => [
        name,
        { options: value },
      ]),
    ),
  })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("import title templates", () => {
  it("keeps the English default titles", () => {
    expect(sqlOf(["invoices", "quotes"], "quotes")).toContain(
      `replace('Quote {number}', '{number}', coalesce(v_number, ''))`,
    );
    expect(sqlOf(["invoices"], "invoices")).toContain(
      `replace('Invoice {number}', '{number}', coalesce(v_number, 'draft'))`,
    );
    expect(sqlOf(["invoices"], "invoices")).toContain(
      `replace('Opening balance {number}', '{number}'`,
    );
  });

  it("renders the configured template per module", () => {
    expect(
      sqlOf(["invoices", "quotes"], "quotes", {
        quotes: { titleTemplate: "Offerte {number}" },
      }),
    ).toContain(
      `replace('Offerte {number}', '{number}', coalesce(v_number, ''))`,
    );

    const invoices = sqlOf(["invoices"], "invoices", {
      invoices: {
        titleTemplate: "Factuur {number}",
        openingTitleTemplate: "Openingssaldo {number}",
      },
    });

    expect(invoices).toContain(`replace('Factuur {number}'`);
    expect(invoices).toContain(`replace('Openingssaldo {number}'`);
    expect(invoices).not.toContain(`'Invoice {number}'`);
  });

  it("renders the checkout invoice title from the orders option", () => {
    const orders = (options: Record<string, Record<string, unknown>> = {}) =>
      sqlOf(["invoices", "orders"], "orders", options);

    expect(orders()).toContain(`replace('Order {number}', '{number}'`);
    expect(
      orders({ orders: { titleTemplate: "Bestelling {number}" } }),
    ).toContain(`replace('Bestelling {number}', '{number}'`);
  });

  it("escapes a quote in the template", () => {
    expect(
      sqlOf(["invoices", "quotes"], "quotes", {
        quotes: { titleTemplate: "Quote d'offre {number}" },
      }),
    ).toContain(`replace('Quote d''offre {number}'`);
  });
});
