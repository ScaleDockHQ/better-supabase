import type { DbError } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type { Money } from "./money.ts";

import { dbError } from "../core/errors.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import {
  applyRate,
  isMoney,
  isRate,
  negateMoney,
  subtractMoney,
  sumMoney,
} from "./money.ts";

/** Where the goods go (or the customer is, for services). */
export interface TaxAddress {
  /** ISO 3166-1 alpha-2, such as `NL`. */
  readonly country: string;
  /** The state or province code, such as `CA`. */
  readonly state?: string;
  readonly postalCode?: string;
  readonly city?: string;
  readonly line1?: string;
  readonly line2?: string;
}

export interface TaxCartLine {
  /** The cart line's id; the quote's line for it carries the same `lineId`. */
  readonly id: string;
  /** The line's total after discounts, in the cart's currency. */
  readonly amount: Money;
  readonly quantity?: number;
  /**
   * The product's tax category: a key of the provider's rates or a provider tax
   * code.
   */
  readonly taxCategory?: string;
  /** The amount already contains the tax (prices shown with VAT). */
  readonly inclusive?: boolean;
}

export interface TaxCart {
  readonly currency: string;
  readonly lines: readonly TaxCartLine[];
  readonly shipping?: {
    readonly amount: Money;
    readonly taxCategory?: string;
    readonly inclusive?: boolean;
  };
  readonly address: TaxAddress;
  readonly customer?: {
    /** The provider's customer id. */
    readonly id?: string;
    /** No tax at all, such as a reverse-charged B2B sale. */
    readonly exempt?: boolean;
  };
  /** The cart or order the quote is for. */
  readonly reference?: string;
}

/** The lineId of the shipping line in a quote. */
export const SHIPPING_LINE = "shipping";

export interface TaxLine {
  /** The cart line's `id`, or `SHIPPING_LINE`. */
  readonly lineId: string;
  /** The amount the tax is computed on, without the tax. */
  readonly taxable: Money;
  readonly tax: Money;
  /** The decimal fraction applied, such as `"0.21"`. */
  readonly rate: string;
  readonly inclusive: boolean;
  /**
   * The jurisdiction: Stripe's name (`Netherlands`) or the `fixedRates` region
   * (`NL`).
   */
  readonly jurisdiction?: string;
  readonly taxCategory?: string;
}

export interface TaxQuote {
  /**
   * The provider's id for the calculation; `commit` turns it into a
   * transaction.
   */
  readonly id: string;
  /** The provider's `name`. */
  readonly provider: string;
  readonly currency: string;
  /** One per cart line, in cart order, then the shipping line when there is one. */
  readonly lines: readonly TaxLine[];
  /** The tax of every line, shipping included. */
  readonly totalTax: Money;
  /** When the provider stops accepting the quote for `commit`. */
  readonly expiresAt?: Temporal.Instant;
}

/** A recorded sale or reversal. Store it with the order to reverse it later. */
export interface TaxTransaction {
  readonly id: string;
  /** The order number for a sale, the refund's id for a reversal. */
  readonly reference: string;
  readonly currency: string;
  /** Negative for a reversal. */
  readonly totalTax: Money;
  readonly lines: readonly TaxLine[];
}

export interface TaxCommitInput {
  readonly quote: TaxQuote;
  /** The order number, unique per sale. */
  readonly reference: string;
}

export interface TaxReverseInput {
  /** The sale `commit` returned. */
  readonly transaction: TaxTransaction;
  /** The refund's id, unique per reversal. */
  readonly reference: string;
  /**
   * The refunded part of each line, as positive amounts without tax and their
   * tax. Unset: the whole sale is reversed.
   */
  readonly lines?: readonly {
    readonly lineId: string;
    readonly amount: Money;
    readonly tax: Money;
  }[];
}

export interface TaxCallOptions {
  /** The same key returns the first call's result instead of recording twice. */
  readonly idempotencyKey?: string;
  readonly signal?: AbortSignal;
}

/**
 * Computes and records sales tax. Versioned: a breaking change ships a new
 * `apiVersion`. Every method returns a `Result`: `invalid_input` for a cart
 * that mixes currencies or a reversal above the sale, and `not_found` for an
 * address the provider has no rate for.
 */
export interface TaxProvider {
  readonly apiVersion: 1;
  readonly name: string;
  quote(cart: TaxCart, options?: TaxCallOptions): AsyncResult<TaxQuote>;
  commit(
    input: TaxCommitInput,
    options?: TaxCallOptions,
  ): AsyncResult<TaxTransaction>;
  reverse(
    input: TaxReverseInput,
    options?: TaxCallOptions,
  ): AsyncResult<TaxTransaction>;
}

/** Checks the provider's `apiVersion` before a block uses it. */
export function taxProviderOf(provider: TaxProvider): TaxProvider {
  const version: unknown = provider.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `tax "${provider.name}" targets tax provider API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the provider for API 1.`,
    );
  }

  return provider;
}

const invalid = (message: string, hint: string): DbError =>
  dbError("invalid_input", message, { hint });

/**
 * The first problem with a cart: a line or shipping amount that isn't money, is
 * negative or is in another currency, or a country that isn't two capital
 * letters.
 */
export function invalidTaxCart(cart: TaxCart): DbError | undefined {
  if (!/^[A-Z]{2}$/.test(cart.address.country)) {
    return invalid(
      `"${cart.address.country}" is not an ISO 3166-1 alpha-2 country code`,
      "TAX_ADDRESS_INVALID",
    );
  }

  const amounts = [
    ...cart.lines.map((line) => line.amount),
    ...(cart.shipping ? [cart.shipping.amount] : []),
  ];

  for (const amount of amounts) {
    if (!isMoney(amount) || amount.amount < 0n) {
      return invalid(
        "Every cart line is Money of zero or more",
        "TAX_AMOUNT_INVALID",
      );
    }

    if (amount.currency !== cart.currency) {
      return invalid(
        `A ${amount.currency} line in a ${cart.currency} cart: lines never mix currencies`,
        "TAX_CURRENCY_MISMATCH",
      );
    }
  }

  return undefined;
}

/** The lines and total of a reversal, checked against the sale. */
export function reversalOf(
  input: TaxReverseInput,
): Result<{ readonly lines: readonly TaxLine[]; readonly totalTax: Money }> {
  const { transaction } = input;

  if (input.lines === undefined) {
    const lines = transaction.lines.map((line) => ({
      ...line,
      taxable: negateMoney(line.taxable),
      tax: negateMoney(line.tax),
    }));

    return ok({ lines, totalTax: negateMoney(transaction.totalTax) });
  }

  const byId = new Map(transaction.lines.map((line) => [line.lineId, line]));
  const lines: TaxLine[] = [];

  for (const part of input.lines) {
    const sold = byId.get(part.lineId);

    if (sold === undefined) {
      return err(
        invalid(
          `The sale has no line "${part.lineId}"`,
          "TAX_REVERSAL_UNKNOWN_LINE",
        ),
      );
    }

    if (
      !isMoney(part.amount) ||
      !isMoney(part.tax) ||
      part.amount.currency !== transaction.currency ||
      part.tax.currency !== transaction.currency ||
      part.amount.amount < 0n ||
      part.tax.amount < 0n ||
      part.tax.amount > sold.tax.amount ||
      part.amount.amount > sold.taxable.amount
    ) {
      return err(
        invalid(
          `The reversal of "${part.lineId}" is not a part of the sold line in ${transaction.currency}`,
          "TAX_REVERSAL_TOO_LARGE",
        ),
      );
    }

    lines.push({
      ...sold,
      taxable: negateMoney(part.amount),
      tax: negateMoney(part.tax),
    });
  }

  return ok({
    lines,
    totalTax: sumMoney(
      lines.map((line) => line.tax),
      transaction.currency,
    ),
  });
}

/** Rates per tax category, such as `{ standard: "0.21", reduced: "0.09" }`. */
export type TaxRates = Readonly<Record<string, string>>;

export interface FixedRatesOptions {
  /** Defaults to `fixed-rates`. */
  readonly name?: string;
  /**
   * Rates per region: a country code (`NL`) or a country and state (`US-CA`),
   * which wins over its country.
   */
  readonly rates: Readonly<Record<string, TaxRates>>;
  /** The category of a line without one. Defaults to `standard`. */
  readonly defaultCategory?: string;
  /** The category of shipping. Defaults to `defaultCategory`. */
  readonly shippingCategory?: string;
  /**
   * A region without rates: `error` returns `not_found` (the default), `zero`
   * quotes no tax.
   */
  readonly unknownRegion?: "error" | "zero";
}

/**
 * A `TaxProvider` with fixed rates per country (and state) and tax category,
 * rounded half to even per line. It keeps nothing: `commit` and `reverse`
 * return the transaction for the app to store.
 */
export function fixedRates(options: FixedRatesOptions): TaxProvider {
  for (const [region, rates] of Object.entries(options.rates)) {
    if (!/^[A-Z]{2}(-[A-Z0-9]{1,3})?$/.test(region)) {
      throw new TypeError(
        `fixedRates: "${region}" is not a country code (NL) or a country and state (US-CA)`,
      );
    }

    for (const [category, rate] of Object.entries(rates)) {
      if (!isRate(rate)) {
        throw new TypeError(
          `fixedRates: the ${region} "${category}" rate "${String(rate)}" is not a decimal fraction such as "0.21"`,
        );
      }
    }
  }

  const name = options.name ?? "fixed-rates";
  const defaultCategory = options.defaultCategory ?? "standard";
  const shippingCategory = options.shippingCategory ?? defaultCategory;

  const regionFor = (
    address: TaxAddress,
  ): { readonly region: string; readonly rates: TaxRates } | undefined => {
    const keys = [
      ...(address.state === undefined
        ? []
        : [`${address.country}-${address.state}`]),
      address.country,
    ];

    for (const region of keys) {
      const rates = options.rates[region];

      if (rates !== undefined) {
        return { region, rates };
      }
    }

    return undefined;
  };

  const lineOf = (
    lineId: string,
    amount: Money,
    category: string,
    inclusive: boolean,
    region: { readonly region: string; readonly rates: TaxRates } | undefined,
    exempt: boolean,
  ): Result<TaxLine> => {
    const rate = exempt || region === undefined ? "0" : region.rates[category];

    if (rate === undefined) {
      return err(
        dbError("not_found", `No "${category}" tax rate for this region`, {
          hint: "TAX_RATE_UNKNOWN",
        }),
      );
    }

    const tax = applyRate(amount, rate, { included: inclusive });

    return ok({
      lineId,
      taxable: inclusive ? subtractMoney(amount, tax) : amount,
      tax,
      rate,
      inclusive,
      ...(region === undefined ? {} : { jurisdiction: region.region }),
      taxCategory: category,
    });
  };

  return {
    apiVersion: 1,
    name,
    quote: (cart) => AsyncResult.from(() => Promise.resolve(quoteOf(cart))),
    commit: ({ quote, reference }) =>
      AsyncResult.ok({
        id: quote.id,
        reference,
        currency: quote.currency,
        totalTax: quote.totalTax,
        lines: quote.lines,
      }),
    reverse: (input) =>
      AsyncResult.from(() => Promise.resolve(reversalOf(input))).map(
        (reversal) => ({
          id: `${input.transaction.id}:${input.reference}`,
          reference: input.reference,
          currency: input.transaction.currency,
          ...reversal,
        }),
      ),
  };

  function quoteOf(cart: TaxCart): Result<TaxQuote> {
    const problem = invalidTaxCart(cart);

    if (problem) {
      return err(problem);
    }

    const rates = regionFor(cart.address);

    if (rates === undefined && options.unknownRegion !== "zero") {
      return err(
        dbError(
          "not_found",
          `No tax rates for ${cart.address.country}${cart.address.state ? `-${cart.address.state}` : ""}`,
          { hint: "TAX_REGION_UNKNOWN" },
        ),
      );
    }

    const exempt = cart.customer?.exempt === true;
    const lines: TaxLine[] = [];

    for (const line of cart.lines) {
      const taxed = lineOf(
        line.id,
        line.amount,
        line.taxCategory ?? defaultCategory,
        line.inclusive === true,
        rates,
        exempt,
      );

      if (!taxed.ok) {
        return taxed;
      }

      lines.push(taxed.data);
    }

    if (cart.shipping) {
      const taxed = lineOf(
        SHIPPING_LINE,
        cart.shipping.amount,
        cart.shipping.taxCategory ?? shippingCategory,
        cart.shipping.inclusive === true,
        rates,
        exempt,
      );

      if (!taxed.ok) {
        return taxed;
      }

      lines.push(taxed.data);
    }

    return ok({
      id: `fixed_${crypto.randomUUID()}`,
      provider: name,
      currency: cart.currency,
      lines,
      totalTax: sumMoney(
        lines.map((line) => line.tax),
        cart.currency,
      ),
    });
  }
}
