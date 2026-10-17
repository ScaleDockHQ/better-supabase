import type { Money } from "../commerce/money.ts";

import { temporal } from "../core/temporal-required.ts";
import { amountText, moneyOf } from "./money-codec.ts";
import { optionalText, recordOf, textOf } from "./shared.ts";

/** A record a sales document points at: a company, a contact, its origin. */
export interface RecordRef {
  readonly type: string;
  readonly id: string;
}

/** A line of a quote or invoice, in the document's currency. */
export interface LineInput {
  readonly description: string;
  readonly quantity?: number;
  readonly unitAmount: Money;
  readonly discountBps?: number;
  readonly taxRateBps?: number;
  readonly taxCode?: string;
  readonly product?: RecordRef;
}

export interface Line extends LineInput {
  readonly quantity: number;
  readonly discountBps: number;
  readonly taxRateBps: number;
}

/** A document's totals, in its currency. */
export interface Totals {
  readonly listTotal: Money;
  readonly discountTotal: Money;
  readonly subtotal: Money;
  readonly taxTotal: Money;
  readonly total: Money;
}

type Loose<T> = { [K in keyof T]: T[K] | undefined };

/** Drops `undefined` properties, which `exactOptionalPropertyTypes` refuses. */
export function compact<T extends object>(value: Loose<T>): T {
  // SAFETY: what is left after dropping undefined keys has the shape of T.
  return Object.fromEntries(
    Object.entries(value).filter(([, item]) => item !== undefined),
  ) as T;
}

export const plainDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string"
    ? temporal().PlainDate.from(value.slice(0, 10))
    : undefined;

export function refOf(type: unknown, id: unknown): RecordRef | undefined {
  const t = optionalText(type);
  const i = optionalText(id);

  return t === undefined || i === undefined ? undefined : { type: t, id: i };
}

/** A line a document function returned, in the document's `currency`. */
export function lineOf(value: unknown, currency: string): Line {
  const row = recordOf(value, "line");
  const product = recordOf(row["product"] ?? {}, "line product");

  return compact<Line>({
    description: textOf(row["description"]),
    quantity: Number(row["quantity"] ?? 1),
    unitAmount: moneyOf(row["unitAmount"], currency, "line unitAmount"),
    discountBps: Number(row["discountBps"] ?? 0),
    taxRateBps: Number(row["taxRateBps"] ?? 0),
    taxCode: optionalText(row["taxCode"]),
    product: refOf(product["type"], product["id"]),
  });
}

/**
 * A document's totals: a row (snake keys) or a `set_*_lines` result (camel
 * keys, with its currency).
 */
export function totalsOf(
  row: Readonly<Record<string, unknown>>,
  camel: boolean,
): Totals {
  const currency = row["currency"];

  const at = (snake: string, camelKey: string): Money =>
    moneyOf(camel ? row[camelKey] : row[snake], currency, camelKey);

  return {
    listTotal: at("list_total", "listTotal"),
    discountTotal: at("discount_total", "discountTotal"),
    subtotal: at("subtotal", "subtotal"),
    taxTotal: at("tax_total", "taxTotal"),
    total: at("total", "total"),
  };
}

/** A line as the database reads it: the unit amount as text, with its currency. */
export const lineArg = (line: LineInput): Record<string, unknown> => ({
  ...line,
  unitAmount: amountText(line.unitAmount),
  currency: line.unitAmount.currency,
});

/** Write attributes as the database reads them: dates as ISO text. */
export function attrsArg(input: object): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(input).map(([key, value]) => [
      key,
      value instanceof temporal().PlainDate ||
      value instanceof temporal().Instant
        ? value.toString()
        : value,
    ]),
  );
}
