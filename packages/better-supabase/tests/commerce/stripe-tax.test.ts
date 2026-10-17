import type Stripe from "stripe";

import { describe, expect, expectTypeOf, it } from "vitest";

import {
  money,
  SHIPPING_LINE,
  type StripeTaxCalculation,
  type StripeTaxCalculationLine,
  type StripeTaxClient,
  stripeTax,
} from "../../src/commerce/index.ts";
import { testTaxProvider } from "../../src/testing/index.ts";

type Params = Readonly<Record<string, unknown>>;

type Line = StripeTaxCalculationLine;

const PAGE = 2;

const page = <T extends { id: string }>(
  items: readonly T[],
  params?: Params,
) => {
  const after = params?.["starting_after"];

  const start =
    after === undefined ? 0 : items.findIndex((item) => item.id === after) + 1;

  return {
    data: items.slice(start, start + PAGE),
    has_more: start + PAGE < items.length,
  };
};

/** Stripe Tax in memory: 21% in NL, 6.25% plus 1% in US-CA, none elsewhere. */
function fakeStripe() {
  const calculations = new Map<string, readonly Line[]>();

  const transactions = new Map<
    string,
    readonly { id: string; reference: string }[]
  >();

  const keys = new Map<string, unknown>();
  const calls: { method: string; params: Params }[] = [];
  let next = 0;

  const breakdownFor = (address: Params) =>
    address["country"] === "NL"
      ? [{ name: "Netherlands", percent: "21.0" }]
      : address["country"] === "US" && address["state"] === "CA"
        ? [
            { name: "California", percent: "6.25" },
            { name: "Los Angeles County", percent: "1.0" },
          ]
        : [];

  const tax = (
    amount: number,
    behavior: string,
    rates: readonly { name: string; percent: string }[],
  ) => {
    const breakdown = rates.map((rate) => {
      const fraction = Number(rate.percent) / 100;

      return {
        amount: Math.round(
          behavior === "inclusive"
            ? (amount * fraction) / (1 + fraction)
            : amount * fraction,
        ),
        jurisdiction: { display_name: rate.name },
        tax_rate_details: { percentage_decimal: rate.percent },
      };
    });

    return {
      amount_tax: breakdown.reduce((sum, entry) => sum + entry.amount, 0),
      tax_breakdown: breakdown,
    };
  };

  const once = <T>(
    options: { readonly idempotencyKey?: string } | undefined,
    work: () => T,
  ): T => {
    const key = options?.idempotencyKey;

    if (key !== undefined && keys.has(key)) {
      return keys.get(key) as T;
    }

    const result = work();

    if (key !== undefined) {
      keys.set(key, result);
    }

    return result;
  };

  const client: StripeTaxClient = {
    tax: {
      calculations: {
        create: async (params) => {
          calls.push({ method: "calculation", params });
          const details = params["customer_details"] as Params;

          const rates =
            details["taxability_override"] === "customer_exempt"
              ? []
              : breakdownFor(details["address"] as Params);

          const lines = params.line_items.map((line): Line => ({
            id: `tax_li_${++next}`,
            reference: line.reference,
            amount: line.amount,
            tax_behavior: String(line["tax_behavior"]),
            tax_code: (line["tax_code"] as string | undefined) ?? null,
            ...tax(line.amount, String(line["tax_behavior"]), rates),
          }));

          const id = `taxcalc_${++next}`;
          calculations.set(id, lines);
          const shipping = params["shipping_cost"] as Params | undefined;

          const calculation: StripeTaxCalculation = {
            id,
            currency: params.currency,
            expires_at: 1_790_000_000,
            line_items: page(lines),
            shipping_cost: shipping
              ? {
                  amount: Number(shipping["amount"]),
                  tax_behavior: String(shipping["tax_behavior"]),
                  ...tax(
                    Number(shipping["amount"]),
                    String(shipping["tax_behavior"]),
                    rates,
                  ),
                }
              : null,
          };

          return calculation;
        },
        listLineItems: async (id, params) =>
          page(calculations.get(id) ?? [], params),
      },
      transactions: {
        createFromCalculation: async (params, options) =>
          once(options, () => {
            calls.push({ method: "commit", params });
            const lines = calculations.get(params.calculation);

            if (!lines) {
              throw new Error("No such calculation");
            }

            const id = `tax_${++next}`;
            transactions.set(
              id,
              lines.map((line) => ({
                id: `${id}_${line.reference}`,
                reference: line.reference,
              })),
            );

            return { id, reference: params.reference };
          }),
        createReversal: async (params, options) =>
          once(options, () => {
            calls.push({ method: "reversal", params });
            const original = transactions.get(params.original_transaction);

            if (!original) {
              throw new Error("No such transaction");
            }

            for (const line of (params["line_items"] as Params[] | undefined) ??
              []) {
              if (
                !original.some((each) => each.id === line["original_line_item"])
              ) {
                throw new Error("No such line item");
              }
            }

            return {
              id: `tax_${++next}`,
              reference: params.reference,
            };
          }),
        listLineItems: async (id, params) =>
          page(transactions.get(id) ?? [], params),
      },
    },
  };

  return { client, calls };
}

const setup = () => {
  const fake = fakeStripe();

  return {
    ...fake,
    provider: stripeTax({
      stripe: fake.client,
      taxCodes: { ebook: "txcd_10302000" },
    }),
  };
};

describe("stripeTax", () => {
  it("passes the TaxProvider conformance kit", async () => {
    const { provider } = setup();

    const report = await testTaxProvider(provider, {
      address: { country: "NL", postalCode: "1011 AB", city: "Amsterdam" },
    });

    expect(report.subject).toBe('TaxProvider "stripe-tax"');
    await testTaxProvider(provider, {
      address: { country: "US", state: "CA", postalCode: "90001" },
      currency: "USD",
    });
    await testTaxProvider(provider, {
      address: { country: "DE" },
      expectTax: false,
    });
  });

  it("sends the cart as a calculation with tax codes and the address", async () => {
    const { provider, calls } = setup();
    await provider
      .quote(
        {
          currency: "EUR",
          address: { country: "NL", line1: "Dam 1", city: "Amsterdam" },
          customer: { id: "cus_1" },
          lines: [
            {
              id: "a",
              amount: money(1000n, "EUR"),
              taxCategory: "ebook",
              quantity: 2,
            },
            {
              id: "b",
              amount: money(500n, "EUR"),
              taxCategory: "txcd_99999999",
            },
            { id: "c", amount: money(500n, "EUR"), taxCategory: "unmapped" },
          ],
          shipping: { amount: money(400n, "EUR"), taxCategory: "ebook" },
        },
        { idempotencyKey: "q1" },
      )
      .orThrow();
    expect(calls[0]?.params).toEqual({
      currency: "eur",
      line_items: [
        {
          amount: 1000,
          reference: "a",
          quantity: 2,
          tax_behavior: "exclusive",
          tax_code: "txcd_10302000",
        },
        {
          amount: 500,
          reference: "b",
          quantity: 1,
          tax_behavior: "exclusive",
          tax_code: "txcd_99999999",
        },
        { amount: 500, reference: "c", quantity: 1, tax_behavior: "exclusive" },
      ],
      shipping_cost: {
        amount: 400,
        tax_behavior: "exclusive",
        tax_code: "txcd_10302000",
      },
      customer_details: {
        address: { country: "NL", city: "Amsterdam", line1: "Dam 1" },
        address_source: "shipping",
      },
      customer: "cus_1",
      expand: ["line_items.data.tax_breakdown"],
    });
  });

  it("reads every page of lines, sums jurisdictions and keeps the expiry", async () => {
    const { provider } = setup();

    const quote = await provider
      .quote({
        currency: "USD",
        address: { country: "US", state: "CA" },
        lines: ["a", "b", "c", "d", "e"].map((id) => ({
          id,
          amount: money(10_000n, "USD"),
        })),
      })
      .orThrow();

    expect(quote.lines.map((line) => line.lineId)).toEqual([
      "a",
      "b",
      "c",
      "d",
      "e",
    ]);
    expect(quote.lines[4]).toEqual({
      lineId: "e",
      taxable: money(10_000n, "USD"),
      tax: money(725n, "USD"),
      rate: "0.0725",
      inclusive: false,
      jurisdiction: "California, Los Angeles County",
    });
    expect(quote.totalTax).toEqual(money(3625n, "USD"));
    expect(quote.expiresAt?.epochMilliseconds).toBe(1_790_000_000_000);
  });

  it("quotes shipping and a zero rate", async () => {
    const { provider } = setup();

    const quote = await provider
      .quote({
        currency: "EUR",
        address: { country: "DE" },
        lines: [{ id: "a", amount: money(100n, "EUR") }],
        shipping: { amount: money(100n, "EUR"), inclusive: true },
      })
      .orThrow();

    expect(quote.lines.at(-1)).toMatchObject({
      lineId: SHIPPING_LINE,
      rate: "0",
      inclusive: true,
      taxable: money(100n, "EUR"),
    });
  });

  it("commits with an idempotency key from the reference", async () => {
    const { provider, calls } = setup();

    const cart = {
      currency: "EUR",
      address: { country: "NL" },
      lines: [{ id: "a", amount: money(1000n, "EUR") }],
    };

    const quote = await provider.quote(cart).orThrow();

    const first = await provider
      .commit({ quote, reference: "order-1" })
      .orThrow();

    const again = await provider
      .commit({ quote, reference: "order-1" })
      .orThrow();

    expect(again.id).toBe(first.id);
    expect(calls.filter((call) => call.method === "commit")).toHaveLength(1);
  });

  it("reverses part of a sale line by line, shipping included", async () => {
    const { provider, calls } = setup();

    const quote = await provider
      .quote({
        currency: "EUR",
        address: { country: "NL" },
        lines: ["a", "b", "c"].map((id) => ({
          id,
          amount: money(1210n, "EUR"),
          inclusive: true,
        })),
        shipping: { amount: money(500n, "EUR") },
      })
      .orThrow();

    const sale = await provider
      .commit({ quote, reference: "order-2" })
      .orThrow();

    const reversal = await provider
      .reverse({
        transaction: sale,
        reference: "refund-1",
        lines: [
          { lineId: "c", amount: money(1000n, "EUR"), tax: money(210n, "EUR") },
          {
            lineId: SHIPPING_LINE,
            amount: money(500n, "EUR"),
            tax: money(105n, "EUR"),
          },
        ],
      })
      .orThrow();

    expect(reversal.totalTax).toEqual(money(-315n, "EUR"));
    expect(calls.at(-1)?.params).toEqual({
      original_transaction: sale.id,
      reference: "refund-1",
      mode: "partial",
      line_items: [
        {
          original_line_item: `${sale.id}_c`,
          reference: "c",
          amount: -1210,
          amount_tax: -210,
        },
      ],
      shipping_cost: { amount: -500, amount_tax: -105 },
    });
  });

  it("refuses a line the Stripe transaction doesn't have", async () => {
    const { provider } = setup();

    const quote = await provider
      .quote({
        currency: "EUR",
        address: { country: "NL" },
        lines: [{ id: "a", amount: money(1000n, "EUR") }],
      })
      .orThrow();

    const sale = await provider
      .commit({ quote, reference: "order-3" })
      .orThrow();

    const forged = {
      ...sale,
      lines: [...sale.lines, { ...sale.lines[0]!, lineId: "ghost" }],
    };

    const result = await provider.reverse({
      transaction: forged,
      reference: "refund-2",
      lines: [
        { lineId: "ghost", amount: money(1n, "EUR"), tax: money(0n, "EUR") },
      ],
    });

    expect(result.ok ? undefined : result.error.hint).toBe(
      "TAX_REVERSAL_UNKNOWN_LINE",
    );
  });

  it("refuses a calculation without an id and maps thrown errors", async () => {
    const fake = fakeStripe();

    const create = fake.client.tax.calculations.create.bind(
      fake.client.tax.calculations,
    );

    fake.client.tax.calculations.create = async (params, options) => ({
      ...(await create(params, options)),
      id: null,
    });
    const provider = stripeTax({ stripe: fake.client, name: "tax" });

    const cart = {
      currency: "EUR",
      address: { country: "NL" },
      lines: [{ id: "a", amount: money(1000n, "EUR") }],
    };

    const result = await provider.quote(cart);
    expect(result.ok ? undefined : result.error.kind).toBe("unexpected");
    fake.client.tax.calculations.create = async () => {
      throw Object.assign(new Error("Invalid address"), {
        type: "StripeInvalidRequestError",
        statusCode: 400,
      });
    };

    const thrown = await provider.quote(cart);
    expect(thrown.ok ? undefined : thrown.error.kind).toBe("invalid_input");

    const precise = await provider.quote({
      ...cart,
      currency: "KWD",
      lines: [{ id: "a", amount: money(1001n, "KWD") }],
    });

    expect(precise.ok ? undefined : precise.error.hint).toBe(
      "STRIPE_AMOUNT_PRECISION",
    );
  });
});

describe("StripeTaxClient", () => {
  it("is satisfied by the Stripe SDK", () => {
    expectTypeOf<Stripe>().toExtend<StripeTaxClient>();
  });
});
