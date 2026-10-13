import type { Money } from "./money.ts";

import { dbError } from "../../core/errors.ts";
import { err, ok, type Result } from "../../core/result.ts";
import { optionalTemporal } from "../../core/temporal.ts";
import { lazyStripe, type StripeSource } from "../stripe.ts";
import {
  fromStripeAmount,
  idempotency,
  stripeResult,
  toStripeAmount,
} from "./stripe-shared.ts";
import {
  invalidTaxCart,
  reversalOf,
  SHIPPING_LINE,
  type TaxAddress,
  type TaxCart,
  type TaxLine,
  type TaxProvider,
  type TaxQuote,
} from "./tax.ts";

type Params = Readonly<Record<string, unknown>>;
type RequestOptions = { readonly idempotencyKey?: string };

type CalculationParams = {
  readonly currency: string;
  readonly line_items: {
    readonly amount: number;
    readonly reference: string;
    readonly [key: string]: unknown;
  }[];
  readonly [key: string]: unknown;
};

type ReversalParams = {
  readonly mode: "full" | "partial";
  readonly original_transaction: string;
  readonly reference: string;
  readonly [key: string]: unknown;
};

interface StripeTaxBreakdown {
  readonly amount: number;
  readonly jurisdiction?: { readonly display_name?: string | null } | null;
  readonly tax_rate_details?: {
    readonly percentage_decimal?: string | null;
  } | null;
}

export interface StripeTaxCalculationLine {
  readonly id: string;
  readonly reference: string;
  readonly amount: number;
  readonly amount_tax: number;
  readonly tax_behavior: string;
  readonly tax_code?: string | null;
  readonly tax_breakdown?: readonly StripeTaxBreakdown[] | null;
}

interface StripeList<T> {
  readonly data: readonly T[];
  readonly has_more: boolean;
}

export interface StripeTaxCalculation {
  readonly id: string | null;
  readonly currency: string;
  readonly expires_at?: number | null;
  readonly line_items?: StripeList<StripeTaxCalculationLine> | null;
  readonly shipping_cost?: {
    readonly amount: number;
    readonly amount_tax: number;
    readonly tax_behavior: string;
    readonly tax_code?: string | null;
    readonly tax_breakdown?: readonly StripeTaxBreakdown[] | null;
  } | null;
}

export interface StripeTaxTransaction {
  readonly id: string;
  readonly reference: string;
}

export interface StripeTaxTransactionLine {
  readonly id: string;
  readonly reference: string;
}

/**
 * The part of the Stripe SDK `stripeTax` calls, typed structurally so the
 * block never imports `stripe`.
 */
export interface StripeTaxClient {
  readonly tax: {
    readonly calculations: {
      create(
        params: CalculationParams,
        options?: RequestOptions,
      ): Promise<StripeTaxCalculation>;
      listLineItems(
        id: string,
        params?: Params,
      ): PromiseLike<StripeList<StripeTaxCalculationLine>>;
    };
    readonly transactions: {
      createFromCalculation(
        params: { readonly calculation: string; readonly reference: string },
        options?: RequestOptions,
      ): Promise<StripeTaxTransaction>;
      createReversal(
        params: ReversalParams,
        options?: RequestOptions,
      ): Promise<StripeTaxTransaction>;
      listLineItems(
        id: string,
        params?: Params,
      ): PromiseLike<StripeList<StripeTaxTransactionLine>>;
    };
  };
}

export interface StripeTaxOptions {
  /** A client, `{ secretKey }` to create one from `stripe`, or a factory. */
  readonly stripe: StripeSource<StripeTaxClient>;
  /** Defaults to `stripe-tax`. */
  readonly name?: string;
  /**
   * Stripe tax codes by `taxCategory`, such as `{ ebook: "txcd_10302000" }`.
   * A category that starts with `txcd_` is passed as is; others without an
   * entry use the account's default tax code.
   */
  readonly taxCodes?: Readonly<Record<string, string>>;
}

const PAGE = 100;

async function allPages<T extends { readonly id: string }>(
  first: StripeList<T> | null | undefined,
  next: (after: string | undefined) => PromiseLike<StripeList<T>>,
): Promise<readonly T[]> {
  if (first && !first.has_more) return first.data;
  const items: T[] = [];
  let after: string | undefined;
  for (;;) {
    const page = await next(after);
    items.push(...page.data);
    const last = page.data.at(-1);
    if (!page.has_more || last === undefined) return items;
    after = last.id;
  }
}

const PERCENT = /^(\d+)(?:\.(\d+))?$/;

/** The summed `percentage_decimal`s of a breakdown as a fraction string: "21.0" gives "0.21". */
function rateOf(
  breakdown: readonly StripeTaxBreakdown[] | null | undefined,
): string {
  let digits = 0;
  const parts: { value: bigint; scale: number }[] = [];
  for (const entry of breakdown ?? []) {
    const match = PERCENT.exec(
      entry.tax_rate_details?.percentage_decimal ?? "",
    );
    if (!match) continue;
    const fraction = match[2] ?? "";
    parts.push({
      value: BigInt(`${match[1] ?? "0"}${fraction}`),
      scale: fraction.length,
    });
    digits = Math.max(digits, fraction.length);
  }
  const sum = parts.reduce(
    (total, part) => total + part.value * 10n ** BigInt(digits - part.scale),
    0n,
  );
  const scale = digits + 2;
  const text = sum.toString().padStart(scale + 1, "0");
  const whole = text.slice(0, -scale);
  const fraction = text.slice(-scale).replace(/0+$/, "");
  return fraction.length === 0 ? whole : `${whole}.${fraction}`;
}

const jurisdictionOf = (
  breakdown: readonly StripeTaxBreakdown[] | null | undefined,
): string | undefined => {
  const names = (breakdown ?? [])
    .filter((entry) => entry.amount !== 0)
    .flatMap((entry) => entry.jurisdiction?.display_name ?? []);
  return names.length === 0 ? undefined : names.join(", ");
};

function lineOf(
  lineId: string,
  currency: string,
  amount: number,
  amountTax: number,
  behavior: string,
  taxCategory: string | undefined,
  breakdown: readonly StripeTaxBreakdown[] | null | undefined,
): TaxLine {
  const inclusive = behavior === "inclusive";
  const tax = fromStripeAmount(amountTax, currency);
  const gross = fromStripeAmount(amount, currency);
  const jurisdiction = jurisdictionOf(breakdown);
  return {
    lineId,
    taxable: inclusive
      ? { amount: gross.amount - tax.amount, currency: gross.currency }
      : gross,
    tax,
    rate: rateOf(breakdown),
    inclusive,
    ...(jurisdiction === undefined ? {} : { jurisdiction }),
    ...(taxCategory === undefined ? {} : { taxCategory }),
  };
}

const addressOf = (address: TaxAddress): Params => ({
  country: address.country,
  ...(address.state === undefined ? {} : { state: address.state }),
  ...(address.postalCode === undefined
    ? {}
    : { postal_code: address.postalCode }),
  ...(address.city === undefined ? {} : { city: address.city }),
  ...(address.line1 === undefined ? {} : { line1: address.line1 }),
});

/**
 * A `TaxProvider` on Stripe Tax: `quote` creates a calculation, `commit` a
 * transaction from it, and `reverse` a full or partial reversal. `stripe`
 * is an optional peer, loaded on first use when `stripe` is `{ secretKey }`.
 */
export function stripeTax(options: StripeTaxOptions): TaxProvider {
  const name = options.name ?? "stripe-tax";
  const client = lazyStripe<StripeTaxClient>(options.stripe);
  const taxCode = (category: string | undefined): Params => {
    if (category === undefined) return {};
    const code = category.startsWith("txcd_")
      ? category
      : options.taxCodes?.[category];
    return code === undefined ? {} : { tax_code: code };
  };
  const stripeAmount = (value: Money): Result<number> => toStripeAmount(value);

  const paramsOf = (cart: TaxCart): Result<CalculationParams> => {
    const lines: CalculationParams["line_items"][number][] = [];
    for (const line of cart.lines) {
      const amount = stripeAmount(line.amount);
      if (!amount.ok) return amount;
      lines.push({
        amount: amount.data,
        reference: line.id,
        quantity: line.quantity ?? 1,
        tax_behavior: line.inclusive === true ? "inclusive" : "exclusive",
        ...taxCode(line.taxCategory),
      });
    }
    let shipping: Params = {};
    if (cart.shipping) {
      const amount = stripeAmount(cart.shipping.amount);
      if (!amount.ok) return amount;
      shipping = {
        shipping_cost: {
          amount: amount.data,
          tax_behavior:
            cart.shipping.inclusive === true ? "inclusive" : "exclusive",
          ...taxCode(cart.shipping.taxCategory),
        },
      };
    }
    const customer = cart.customer;
    return ok({
      currency: cart.currency.toLowerCase(),
      line_items: lines,
      ...shipping,
      customer_details: {
        address: addressOf(cart.address),
        address_source: "shipping",
        ...(customer?.exempt === true
          ? { taxability_override: "customer_exempt" }
          : {}),
      },
      ...(customer?.id === undefined ? {} : { customer: customer.id }),
      expand: ["line_items.data.tax_breakdown"],
    });
  };

  return {
    apiVersion: 1,
    name,
    quote: (cart, call = {}) =>
      stripeResult(async () => {
        const problem = invalidTaxCart(cart);
        if (problem) return err(problem);
        const params = paramsOf(cart);
        if (!params.ok) return params;
        const stripe = await client();
        const calculation = await stripe.tax.calculations.create(
          params.data,
          idempotency(call.idempotencyKey),
        );
        const id = calculation.id;
        if (id === null)
          return err(
            dbError(
              "unexpected",
              "Stripe returned a calculation without an id",
            ),
          );
        const stripeLines = await allPages(calculation.line_items, (after) =>
          stripe.tax.calculations.listLineItems(id, {
            limit: PAGE,
            expand: ["data.tax_breakdown"],
            ...(after === undefined ? {} : { starting_after: after }),
          }),
        );
        const categories = new Map(
          cart.lines.map((line) => [line.id, line.taxCategory]),
        );
        const lines = stripeLines.map((line) =>
          lineOf(
            line.reference,
            calculation.currency,
            line.amount,
            line.amount_tax,
            line.tax_behavior,
            categories.get(line.reference),
            line.tax_breakdown,
          ),
        );
        const shipping = calculation.shipping_cost;
        if (shipping && cart.shipping)
          lines.push(
            lineOf(
              SHIPPING_LINE,
              calculation.currency,
              shipping.amount,
              shipping.amount_tax,
              shipping.tax_behavior,
              cart.shipping.taxCategory,
              shipping.tax_breakdown,
            ),
          );
        const totalTax = lines.reduce(
          (total, line) => total + line.tax.amount,
          0n,
        );
        const Temporal = optionalTemporal();
        const quote: TaxQuote = {
          id,
          provider: name,
          currency: cart.currency,
          lines,
          totalTax: { amount: totalTax, currency: cart.currency },
          ...(calculation.expires_at && Temporal
            ? {
                expiresAt: Temporal.Instant.fromEpochMilliseconds(
                  calculation.expires_at * 1000,
                ),
              }
            : {}),
        };
        return ok(quote);
      }),
    commit: ({ quote, reference }, call = {}) =>
      stripeResult(async () => {
        const transaction = await (
          await client()
        ).tax.transactions.createFromCalculation(
          { calculation: quote.id, reference },
          idempotency(call.idempotencyKey ?? `tax-commit:${reference}`),
        );
        return ok({
          id: transaction.id,
          reference,
          currency: quote.currency,
          totalTax: quote.totalTax,
          lines: quote.lines,
        });
      }),
    reverse: (input, call = {}) =>
      stripeResult(async () => {
        const reversal = reversalOf(input);
        if (!reversal.ok) return reversal;
        const stripe = await client();
        const key = idempotency(
          call.idempotencyKey ?? `tax-reverse:${input.reference}`,
        );
        const base = {
          original_transaction: input.transaction.id,
          reference: input.reference,
        };
        let params: ReversalParams = { ...base, mode: "full" };
        if (input.lines !== undefined) {
          const originals = await allPages(undefined, (after) =>
            stripe.tax.transactions.listLineItems(input.transaction.id, {
              limit: PAGE,
              ...(after === undefined ? {} : { starting_after: after }),
            }),
          );
          const byReference = new Map(
            originals.map((line) => [line.reference, line.id]),
          );
          const lineItems: Params[] = [];
          let shipping: Params = {};
          for (const line of reversal.data.lines) {
            const amount = stripeAmount(line.taxable);
            const tax = stripeAmount(line.tax);
            if (!amount.ok) return amount;
            if (!tax.ok) return tax;
            const gross = line.inclusive ? amount.data + tax.data : amount.data;
            if (line.lineId === SHIPPING_LINE) {
              shipping = {
                shipping_cost: { amount: gross, amount_tax: tax.data },
              };
              continue;
            }
            const original = byReference.get(line.lineId);
            if (original === undefined)
              return err(
                dbError(
                  "not_found",
                  `The Stripe transaction has no line "${line.lineId}"`,
                  { hint: "TAX_REVERSAL_UNKNOWN_LINE" },
                ),
              );
            lineItems.push({
              original_line_item: original,
              reference: line.lineId,
              amount: gross,
              amount_tax: tax.data,
            });
          }
          params = {
            ...base,
            mode: "partial",
            line_items: lineItems,
            ...shipping,
          };
        }
        const transaction = await stripe.tax.transactions.createReversal(
          params,
          key,
        );
        return ok({
          id: transaction.id,
          reference: input.reference,
          currency: input.transaction.currency,
          ...reversal.data,
        });
      }),
  };
}
