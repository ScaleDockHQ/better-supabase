import type { DbError } from "../core/errors.ts";

import { isCurrency, type Money, money } from "../commerce/money.ts";
import { bigintOf, optionalBigintOf } from "../core/block-helpers.ts";
import { dbError } from "../core/errors.ts";

/**
 * `Money` from an amount block functions send as text and its currency. Throws
 * for a number (precision is already lost), a missing amount or a code ISO 4217
 * doesn't list.
 */
export const moneyOf = (
  amount: unknown,
  currency: unknown,
  field = "amount",
): Money => money(bigintOf(amount, field), String(currency));

/** `moneyOf`, or `undefined` when the amount is null. */
export function optionalMoneyOf(
  amount: unknown,
  currency: unknown,
  field = "amount",
): Money | undefined {
  const found = optionalBigintOf(amount, field);

  return found === undefined ? undefined : money(found, String(currency));
}

/** A `Money` as a function argument: minor units as text. */
export const amountText = (value: Money): string => value.amount.toString();

/** An optional `Money` as a function argument, `null` when absent. */
export const optionalAmountText = (
  value: Money | undefined | null,
): string | null =>
  value === undefined || value === null ? null : amountText(value);

/**
 * The `invalid_request` error for amounts that don't share `currency`, or
 * `undefined` when they all do. Amounts that are `undefined` are skipped.
 */
export function currencyMismatch(
  currency: string | undefined,
  amounts: readonly (Money | undefined)[],
): DbError | undefined {
  const present = amounts.filter((item) => item !== undefined);
  const expected = currency ?? present[0]?.currency;
  const other = present.find((item) => item.currency !== expected);

  return other === undefined || expected === undefined
    ? undefined
    : dbError(
        "invalid_request",
        `Can't combine ${expected} and ${other.currency}: amounts must share one currency`,
        { hint: "CURRENCY_MISMATCH" },
      );
}

/** The `invalid_request` error for a currency ISO 4217 doesn't list. */
export const unknownCurrency = (currency: string): DbError =>
  dbError("invalid_request", `${currency} is not an ISO 4217 currency code`, {
    hint: "CURRENCY_INVALID",
  });

/**
 * Why amounts can't be written in `currency`, or `undefined` when they can: the
 * currency is unknown, or an amount is in another one.
 */
export function amountsError(
  currency: string | undefined,
  amounts: readonly (Money | undefined)[],
): DbError | undefined {
  if (currency !== undefined && !isCurrency(currency)) {
    return unknownCurrency(currency);
  }

  return currencyMismatch(currency, amounts);
}
