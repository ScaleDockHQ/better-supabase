import type { Money } from "../commerce/money.ts";
import type { RecordRef } from "./sales-shared.ts";

import { amountText, moneyOf } from "./money-codec.ts";
import { compact, refOf } from "./sales-shared.ts";
import { optionalText, recordOf, textOf } from "./shared.ts";

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

/**
 * A line that names a catalog product variant and leaves its price, its
 * description or both to the catalog (quotes with the catalog block).
 */
export interface CatalogLineInput extends Omit<
  LineInput,
  "description" | "unitAmount"
> {
  readonly product: RecordRef;
  readonly description?: string;
  readonly unitAmount?: Money;
}

/** A line as the database reads it: the unit amount as text, with its currency. */
export const lineArg = (
  line: LineInput | CatalogLineInput,
): Record<string, unknown> =>
  line.unitAmount === undefined
    ? { ...line }
    : {
        ...line,
        unitAmount: amountText(line.unitAmount),
        currency: line.unitAmount.currency,
      };

/** The unit amounts a list of lines sets, for the currency checks. */
export const lineAmounts = (
  lines: readonly (LineInput | CatalogLineInput)[],
): readonly Money[] =>
  lines.flatMap((line) =>
    line.unitAmount === undefined ? [] : [line.unitAmount],
  );
