import { type DbError, dbError } from "../core/errors.ts";
import {
  AsyncResult,
  err,
  ok,
  type Result,
  toDbError,
} from "../core/result.ts";
import { type Money, minorUnits, money } from "./money.ts";

/**
 * Stripe's decimals where they differ from ISO 4217 (docs.stripe.com/currencies):
 * ISK and UGX keep two for backward compatibility, MGA has none.
 */
const STRIPE_DECIMALS: Readonly<Record<string, number>> = {
  ISK: 2,
  UGX: 2,
  MGA: 0,
};

/** Three-decimal currencies Stripe charges only in multiples of 10. */
const STRIPE_ROUND_TO_TEN = new Set(["BHD", "JOD", "KWD", "OMR", "TND"]);

const stripeDecimals = (currency: string): number =>
  STRIPE_DECIMALS[currency] ?? minorUnits(currency);

/** The `amount` Stripe takes for `value`, or the error when Stripe can't charge it exactly. */
export function toStripeAmount(value: Money): Result<number> {
  const shift = stripeDecimals(value.currency) - minorUnits(value.currency);
  const scale = 10n ** BigInt(Math.abs(shift));

  if (shift < 0 && value.amount % scale !== 0n) {
    return err(
      dbError(
        "invalid_input",
        `Stripe charges ${value.currency} in whole units only`,
        { hint: "STRIPE_AMOUNT_PRECISION" },
      ),
    );
  }

  if (STRIPE_ROUND_TO_TEN.has(value.currency) && value.amount % 10n !== 0n) {
    return err(
      dbError(
        "invalid_input",
        `Stripe charges ${value.currency} in multiples of 10 minor units`,
        { hint: "STRIPE_AMOUNT_PRECISION" },
      ),
    );
  }

  const amount = shift < 0 ? value.amount / scale : value.amount * scale;

  if (amount > BigInt(Number.MAX_SAFE_INTEGER)) {
    return err(
      dbError("invalid_input", "The amount is too large for Stripe", {
        hint: "STRIPE_AMOUNT_PRECISION",
      }),
    );
  }

  return ok(Number(amount));
}

/**
 * `Money` from a Stripe `amount` and its lowercase currency, or the error
 * when the amount has a fraction of the currency's minor unit (an ISK or UGX
 * amount that isn't a multiple of 100).
 */
export function fromStripeAmount(
  amount: number,
  currency: string,
): Result<Money> {
  const code = currency.toUpperCase();
  const shift = stripeDecimals(code) - minorUnits(code);
  const scale = 10n ** BigInt(Math.abs(shift));

  if (!Number.isSafeInteger(amount)) {
    return err(
      dbError("invalid_input", `Stripe sent a fractional ${code} amount`, {
        hint: "STRIPE_AMOUNT_PRECISION",
      }),
    );
  }

  const value = BigInt(amount);

  if (shift > 0 && value % scale !== 0n) {
    return err(
      dbError(
        "invalid_input",
        `Stripe sent a ${code} amount with a fraction of a minor unit`,
        { hint: "STRIPE_AMOUNT_PRECISION" },
      ),
    );
  }

  return ok(money(shift < 0 ? value * scale : value / scale, code));
}

/**
 * A thrown Stripe error as a `DbError`: a declined card is `raised` with
 * the hint `PAYMENT_DECLINED`, a missing object `not_found`, a bad request
 * `invalid_input`, and the rest by HTTP status.
 */
export function stripeError(cause: unknown): DbError {
  if (typeof cause !== "object" || cause === null) {
    return toDbError(cause);
  }

  const fields: Readonly<Record<string, unknown>> = { ...cause };
  const { type, statusCode: status, code } = fields;

  const message =
    cause instanceof Error ? cause.message : String(fields["message"]);

  const extra = typeof code === "string" ? { code } : {};

  if (type === "StripeCardError") {
    return dbError("raised", message, { hint: "PAYMENT_DECLINED", ...extra });
  }

  if (code === "resource_missing" || status === 404) {
    return dbError("not_found", message, extra);
  }

  if (type === "StripeIdempotencyError" || status === 409) {
    return dbError("conflict", message, extra);
  }

  if (type === "StripeRateLimitError" || status === 429) {
    return dbError("rate_limited", message, extra);
  }

  if (type === "StripeAuthenticationError" || status === 401) {
    return dbError("unauthorized", message, extra);
  }

  if (type === "StripePermissionError" || status === 403) {
    return dbError("forbidden", message, extra);
  }

  if (type === "StripeInvalidRequestError" || status === 400) {
    return dbError("invalid_input", message, extra);
  }

  if (type === "StripeConnectionError") {
    return dbError("network", message, extra);
  }

  return toDbError(cause);
}

/** Runs Stripe calls as a result, mapping a thrown Stripe error with `stripeError`. */
export function stripeResult<T>(
  work: () => Promise<Result<T>>,
): AsyncResult<T> {
  return AsyncResult.from(async () => {
    try {
      return await work();
    } catch (cause) {
      return err(stripeError(cause));
    }
  });
}

/** Stripe request options for an idempotency key, when there is one. */
export const idempotency = (
  key: string | undefined,
): { readonly idempotencyKey?: string } =>
  key === undefined ? {} : { idempotencyKey: key };
