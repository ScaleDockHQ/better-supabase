import { temporal } from "../core/temporal-required.ts";
import { optionalText, recordOf, textOf } from "./shared.ts";

/** A record a sales document points at: a company, a contact, its origin. */
export interface RecordRef {
  readonly type: string;
  readonly id: string;
}

/** A line of a quote or invoice. Amounts are minor units. */
export interface LineInput {
  readonly description: string;
  readonly quantity?: number;
  readonly unitAmount: bigint;
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

/** A document's totals in minor units. */
export interface Totals {
  readonly listTotal: bigint;
  readonly discountTotal: bigint;
  readonly subtotal: bigint;
  readonly taxTotal: bigint;
  readonly total: bigint;
}

type Loose<T> = { [K in keyof T]: T[K] | undefined };

/** Drops `undefined` properties, which `exactOptionalPropertyTypes` refuses. */
export function compact<T extends object>(value: Loose<T>): T {
  // SAFETY: what is left after dropping undefined keys has the shape of T.
  return Object.fromEntries(
    Object.entries(value).filter(([, item]) => item !== undefined),
  ) as T;
}

export const big = (value: unknown): bigint =>
  typeof value === "string" || typeof value === "number" ? BigInt(value) : 0n;

export const plainDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string"
    ? temporal().PlainDate.from(value.slice(0, 10))
    : undefined;

export function refOf(type: unknown, id: unknown): RecordRef | undefined {
  const t = optionalText(type);
  const i = optionalText(id);

  return t === undefined || i === undefined ? undefined : { type: t, id: i };
}

export function lineOf(value: unknown): Line {
  const row = recordOf(value, "line");
  const product = recordOf(row["product"] ?? {}, "line product");

  return compact<Line>({
    description: textOf(row["description"]),
    quantity: Number(row["quantity"] ?? 1),
    unitAmount: big(row["unitAmount"]),
    discountBps: Number(row["discountBps"] ?? 0),
    taxRateBps: Number(row["taxRateBps"] ?? 0),
    taxCode: optionalText(row["taxCode"]),
    product: refOf(product["type"], product["id"]),
  });
}

export function totalsOf(row: Record<string, unknown>, camel: boolean): Totals {
  const key = (snake: string, camelKey: string): unknown =>
    camel ? row[camelKey] : row[snake];

  return {
    listTotal: big(key("list_total", "listTotal")),
    discountTotal: big(key("discount_total", "discountTotal")),
    subtotal: big(key("subtotal", "subtotal")),
    taxTotal: big(key("tax_total", "taxTotal")),
    total: big(key("total", "total")),
  };
}

/** A line as the database reads it: the unit amount as text. */
export const lineArg = (line: LineInput): Record<string, unknown> => ({
  ...line,
  unitAmount: line.unitAmount.toString(),
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
