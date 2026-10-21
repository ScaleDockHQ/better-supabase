import { describe, expect, it } from "vitest";

import type { TaxCart, TaxProvider } from "../../src/commerce/index.ts";

import {
  fixedRates,
  money,
  reversalOf,
  SHIPPING_LINE,
  taxProviderOf,
} from "../../src/commerce/index.ts";
import { ConformanceError, testTaxProvider } from "../../src/testing/index.ts";

const eur = (amount: bigint) => money(amount, "EUR");

const provider = fixedRates({
  rates: {
    NL: { standard: "0.21", reduced: "0.09" },
    US: { standard: "0" },
    "US-CA": { standard: "0.0725" },
  },
});

const cart = (overrides: Partial<TaxCart> = {}): TaxCart => ({
  currency: "EUR",
  address: { country: "NL" },
  lines: [
    { id: "book", amount: eur(2000n), taxCategory: "reduced" },
    { id: "pen", amount: eur(500n) },
  ],
  ...overrides,
});

describe("fixedRates", () => {
  it("passes the TaxProvider conformance kit", async () => {
    const report = await testTaxProvider(provider, {
      address: { country: "NL" },
    });

    expect(report.checks.every((check) => check.ok)).toBe(true);
    await testTaxProvider(provider, {
      address: { country: "US" },
      currency: "USD",
      expectTax: false,
    });
  });

  it("quotes each line with its category's rate", async () => {
    const quote = await provider.quote(cart()).orThrow();
    expect(quote.provider).toBe("fixed-rates");
    expect(quote.id).toMatch(/^fixed_/);
    expect(quote.lines).toEqual([
      {
        lineId: "book",
        taxable: eur(2000n),
        tax: eur(180n),
        rate: "0.09",
        inclusive: false,
        jurisdiction: "NL",
        taxCategory: "reduced",
      },
      {
        lineId: "pen",
        taxable: eur(500n),
        tax: eur(105n),
        rate: "0.21",
        inclusive: false,
        jurisdiction: "NL",
        taxCategory: "standard",
      },
    ]);
    expect(quote.totalTax).toEqual(eur(285n));
  });

  it("prefers a state's rates over its country's", async () => {
    const quote = await provider
      .quote(
        cart({
          currency: "USD",
          address: { country: "US", state: "CA" },
          lines: [{ id: "a", amount: money(10_000n, "USD") }],
        }),
      )
      .orThrow();

    expect(quote.lines[0]?.tax).toEqual(money(725n, "USD"));
    expect(quote.lines[0]?.jurisdiction).toBe("US-CA");
  });

  it("taxes shipping with its own category", async () => {
    const shipped = fixedRates({
      rates: { NL: { standard: "0.21", reduced: "0.09" } },
      shippingCategory: "reduced",
    });

    const quote = await shipped
      .quote(cart({ shipping: { amount: eur(1000n), inclusive: true } }))
      .orThrow();

    expect(quote.lines.at(-1)).toMatchObject({
      lineId: SHIPPING_LINE,
      taxable: eur(917n),
      tax: eur(83n),
      inclusive: true,
    });
  });

  it("refuses an unknown region or category, unless told to quote zero", async () => {
    const abroad = await provider.quote(cart({ address: { country: "DE" } }));
    expect(abroad.ok ? undefined : abroad.error.hint).toBe(
      "TAX_REGION_UNKNOWN",
    );

    const state = await provider.quote(
      cart({ address: { country: "DE", state: "BY" } }),
    );

    expect(state.ok ? undefined : state.error.message).toContain("DE-BY");

    const category = await provider.quote(
      cart({ lines: [{ id: "a", amount: eur(1n), taxCategory: "luxury" }] }),
    );

    expect(category.ok ? undefined : category.error).toMatchObject({
      kind: "not_found",
      hint: "TAX_RATE_UNKNOWN",
    });
    const lenient = fixedRates({ rates: {}, unknownRegion: "zero" });
    const zero = await lenient.quote(cart()).orThrow();
    expect(zero.totalTax).toEqual(eur(0n));
    expect(zero.lines.map((line) => line.rate)).toEqual(["0", "0"]);
  });

  it("refuses bad carts", async () => {
    const negative = await provider.quote(
      cart({ lines: [{ id: "a", amount: eur(-1n) }] }),
    );

    expect(negative.ok ? undefined : negative.error.hint).toBe(
      "TAX_AMOUNT_INVALID",
    );

    const mixed = await provider.quote(
      cart({ shipping: { amount: money(1n, "USD") } }),
    );

    expect(mixed.ok ? undefined : mixed.error.hint).toBe(
      "TAX_CURRENCY_MISMATCH",
    );
    const lower = await provider.quote(cart({ address: { country: "nl" } }));
    expect(lower.ok ? undefined : lower.error.hint).toBe("TAX_ADDRESS_INVALID");
  });

  it("validates its rates when it is created", () => {
    expect(() => fixedRates({ rates: { Netherlands: {} } })).toThrow(
      /country code/,
    );
    expect(() => fixedRates({ rates: { NL: { standard: "21%" } } })).toThrow(
      /decimal fraction/,
    );
  });

  it("names reversals after the sale and the refund", async () => {
    const quote = await provider.quote(cart()).orThrow();

    const sale = await provider
      .commit({ quote, reference: "order-1" })
      .orThrow();

    const reversal = await provider
      .reverse({ transaction: sale, reference: "refund-1" })
      .orThrow();

    expect(reversal.id).toBe(`${quote.id}:refund-1`);
    expect(reversal.totalTax).toEqual(eur(-285n));
  });
});

describe("reversalOf", () => {
  const sale = {
    id: "t",
    reference: "order",
    currency: "EUR",
    totalTax: eur(210n),
    lines: [
      {
        lineId: "a",
        taxable: eur(1000n),
        tax: eur(210n),
        rate: "0.21",
        inclusive: false,
      },
    ],
  };

  it("refuses a part in another currency or below zero", () => {
    const usd = reversalOf({
      transaction: sale,
      reference: "r",
      lines: [{ lineId: "a", amount: money(1n, "USD"), tax: eur(0n) }],
    });

    expect(usd.ok).toBe(false);

    const negative = reversalOf({
      transaction: sale,
      reference: "r",
      lines: [{ lineId: "a", amount: eur(-1n), tax: eur(0n) }],
    });

    expect(negative.ok ? undefined : negative.error.hint).toBe(
      "TAX_REVERSAL_TOO_LARGE",
    );
  });
});

describe("taxProviderOf", () => {
  it("accepts API 1 and refuses another", () => {
    expect(taxProviderOf(provider)).toBe(provider);
    const future = { ...provider, apiVersion: 2 } as unknown as TaxProvider;
    expect(() => taxProviderOf(future)).toThrow(/tax provider API 2/);
  });
});

describe("testTaxProvider", () => {
  it("fails a provider that drops lines", async () => {
    const lossy: TaxProvider = {
      ...provider,
      name: "lossy",
      quote: (input, options) =>
        provider
          .quote(input, options)
          .map((quote) => ({ ...quote, lines: quote.lines.slice(1) })),
    };

    await expect(
      testTaxProvider(lossy, { address: { country: "NL" } }),
    ).rejects.toThrow(ConformanceError);
  });
});
