import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

/** Valibot parts the operations actions share for form and button input. */
export const Id = v.pipe(v.string(), v.uuid());

export const Name = v.pipe(
  v.string(),
  v.trim(),
  v.minLength(1),
  v.maxLength(200),
);

export const IsoDate = v.pipe(v.string(), v.isoDate());

/** An empty form field is `""`; it means "not given". */
export const Optional = v.pipe(
  v.optional(v.string(), ""),
  v.trim(),
  v.maxLength(2000),
  v.transform((value) => (value === "" ? undefined : value)),
);

/** A whole number a form sends as text and a button sends as a number. */
export const Whole = (min: number, max: number) =>
  v.pipe(
    v.union([v.string(), v.number()]),
    v.transform(Number),
    v.integer(),
    v.minValue(min),
    v.maxValue(max),
  );

/** A decimal a form sends as text, such as `12.50`. */
export const Decimal = v.pipe(
  v.string(),
  v.trim(),
  v.regex(/^\d+(\.\d{1,3})?$/u),
);

/**
 * `{ [key]: value }` when a value is given, `{}` otherwise, for exact optional
 * properties.
 */
export function given<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: the object holds the key only when `value` is defined.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

/** The plain date a form field holds, or `undefined` when empty or invalid. */
export function plainDateOf(
  value: string | undefined,
): Temporal.PlainDate | undefined {
  return value !== undefined && v.is(IsoDate, value)
    ? Temporal.PlainDate.from(value)
    : undefined;
}

/** Midnight UTC of a form date, as an instant. */
export function instantOf(
  value: string | undefined,
): Temporal.Instant | undefined {
  return value !== undefined && v.is(IsoDate, value)
    ? Temporal.Instant.from(`${value}T00:00:00Z`)
    : undefined;
}

/**
 * A decimal text from the database without its trailing zeros: `12.000000` is
 * `12`.
 */
export function trimmed(value: string | null | undefined): string {
  return value === null || value === undefined || value === ""
    ? "–"
    : String(Number(value));
}
