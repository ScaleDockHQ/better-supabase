import type { Money } from "../../commerce/money.ts";
import type {
  TaxAddress,
  TaxCart,
  TaxProvider,
  TaxQuote,
} from "../../commerce/tax.ts";
import type { Result } from "../../core/result.ts";

import { isRate, money } from "../../commerce/money.ts";
import { SHIPPING_LINE } from "../../commerce/tax.ts";
import { type ConformanceReport, conform, expect } from "../conformance.ts";

export interface TestTaxProviderOptions {
  /** An address the provider taxes, such as `{ country: "NL" }`. */
  readonly address: TaxAddress;
  /** Defaults to `EUR`. */
  readonly currency?: string;
  /** The category of the kit's lines; unset uses the provider's default. */
  readonly taxCategory?: string;
  /** The address has tax above zero. Defaults to `true`. */
  readonly expectTax?: boolean;
}

const kindOf = (result: Result<unknown>): string =>
  result.ok ? "ok" : result.error.kind;

const sum = (values: readonly Money[]): bigint =>
  values.reduce((total, value) => total + value.amount, 0n);

/**
 * Runs the `TaxProvider` contract against `provider`: the API version,
 * refused carts, a quote with one line per cart line in order and a total
 * that adds up, inclusive prices, shipping, exempt customers, commit, and
 * full and partial reversals with their limits. Every commit carries a
 * fresh reference, so the kit runs against a test account without cleanup.
 */
export function testTaxProvider(
  provider: TaxProvider,
  options: TestTaxProviderOptions,
): Promise<ConformanceReport> {
  const currency = options.currency ?? "EUR";
  const { address, taxCategory } = options;
  const expectTax = options.expectTax ?? true;
  const line = (id: string, minor: bigint, inclusive = false) => ({
    id,
    amount: money(minor, currency),
    inclusive,
    ...(taxCategory === undefined ? {} : { taxCategory }),
  });
  const cart = (overrides: Partial<TaxCart> = {}): TaxCart => ({
    currency,
    address,
    lines: [line("a", 10_000n), line("b", 2500n)],
    ...overrides,
  });
  const reference = (): string => `conformance-${crypto.randomUUID()}`;
  const committed = async () => {
    const quote = await provider.quote(cart()).orThrow();
    return provider.commit({ quote, reference: reference() }).orThrow();
  };
  const addsUp = (quote: TaxQuote): void => {
    expect(
      quote.totalTax.amount === sum(quote.lines.map((each) => each.tax)),
      "totalTax is not the sum of the lines' tax",
    );
    for (const each of quote.lines) {
      expect(isRate(each.rate), `line ${each.lineId} has rate "${each.rate}"`);
      expect(
        each.tax.currency === currency && each.taxable.currency === currency,
        `line ${each.lineId} is not in ${currency}`,
      );
    }
  };

  return conform(`TaxProvider "${provider.name}"`, [
    [
      "has apiVersion 1 and a name",
      () => {
        const version: unknown = provider.apiVersion;
        expect(version === 1, `apiVersion is ${String(version)}`);
        expect(provider.name.length > 0, "name is empty");
      },
    ],
    [
      "refuses a cart that mixes currencies or has no country",
      async () => {
        const other = currency === "USD" ? "EUR" : "USD";
        const mixed = await provider.quote(
          cart({ lines: [{ id: "a", amount: money(100n, other) }] }),
        );
        expect(
          kindOf(mixed) === "invalid_input",
          `mixed currencies gave ${kindOf(mixed)}`,
        );
        const nowhere = await provider.quote(
          cart({ address: { ...address, country: "" } }),
        );
        expect(
          kindOf(nowhere) === "invalid_input",
          `no country gave ${kindOf(nowhere)}`,
        );
      },
    ],
    [
      "quotes one line per cart line, in order, with a total that adds up",
      async () => {
        const quote = await provider.quote(cart()).orThrow();
        expect(
          quote.provider === provider.name,
          `provider is ${quote.provider}`,
        );
        expect(
          quote.lines.map((each) => each.lineId).join() === "a,b",
          `lines are ${quote.lines.map((each) => each.lineId).join()}`,
        );
        expect(
          quote.lines[0]?.taxable.amount === 10_000n,
          "line a lost its amount",
        );
        addsUp(quote);
        expect(
          expectTax ? quote.totalTax.amount > 0n : quote.totalTax.amount === 0n,
          `totalTax is ${String(quote.totalTax.amount)}`,
        );
      },
    ],
    [
      "splits an inclusive price into taxable and tax",
      async () => {
        const quote = await provider
          .quote(cart({ lines: [line("a", 12_100n, true)] }))
          .orThrow();
        const only = quote.lines[0];
        expect(only?.inclusive === true, "the line is not inclusive");
        expect(
          only.taxable.amount + only.tax.amount === 12_100n,
          "taxable and tax don't add up to the price",
        );
      },
    ],
    [
      "quotes shipping as the last line",
      async () => {
        const quote = await provider
          .quote(cart({ shipping: { amount: money(500n, currency) } }))
          .orThrow();
        expect(
          quote.lines.at(-1)?.lineId === SHIPPING_LINE,
          "the last line is not shipping",
        );
        addsUp(quote);
      },
    ],
    [
      "charges an exempt customer no tax",
      async () => {
        const quote = await provider
          .quote(cart({ customer: { exempt: true } }))
          .orThrow();
        expect(
          quote.totalTax.amount === 0n,
          `totalTax is ${String(quote.totalTax.amount)}`,
        );
      },
    ],
    [
      "commits a quote as a transaction",
      async () => {
        const quote = await provider.quote(cart()).orThrow();
        const ref = reference();
        const transaction = await provider
          .commit({ quote, reference: ref })
          .orThrow();
        expect(transaction.id.length > 0, "the transaction has no id");
        expect(transaction.reference === ref, "the reference changed");
        expect(
          transaction.totalTax.amount === quote.totalTax.amount,
          "the transaction's tax differs from the quote",
        );
      },
    ],
    [
      "reverses a whole sale",
      async () => {
        const sale = await committed();
        const reversal = await provider
          .reverse({ transaction: sale, reference: reference() })
          .orThrow();
        expect(
          reversal.totalTax.amount === -sale.totalTax.amount,
          `reversed ${String(reversal.totalTax.amount)} of ${String(sale.totalTax.amount)}`,
        );
      },
    ],
    [
      "reverses part of a line and refuses more than was sold",
      async () => {
        const sale = await committed();
        const sold = sale.lines[0];
        expect(sold !== undefined, "the sale has no lines");
        const part = {
          lineId: sold.lineId,
          amount: money(sold.taxable.amount / 2n, currency),
          tax: money(sold.tax.amount / 2n, currency),
        };
        const reversal = await provider
          .reverse({ transaction: sale, reference: reference(), lines: [part] })
          .orThrow();
        expect(
          reversal.totalTax.amount === -part.tax.amount,
          `reversed ${String(reversal.totalTax.amount)}`,
        );
        const tooMuch = await provider.reverse({
          transaction: sale,
          reference: reference(),
          lines: [
            { ...part, amount: money(sold.taxable.amount + 1n, currency) },
          ],
        });
        expect(
          kindOf(tooMuch) === "invalid_input",
          `reversing more than was sold gave ${kindOf(tooMuch)}`,
        );
        const unknown = await provider.reverse({
          transaction: sale,
          reference: reference(),
          lines: [{ ...part, lineId: "conformance-unknown" }],
        });
        expect(
          kindOf(unknown) === "invalid_input",
          `an unknown line gave ${kindOf(unknown)}`,
        );
      },
    ],
  ]);
}
