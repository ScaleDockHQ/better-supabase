import type { Codec } from "../schema/types.ts";

import { DbException, dbError } from "../core/errors.ts";
import { temporal } from "../core/temporal-required.ts";
import { temporalText } from "../core/temporal.ts";

/** ISO text of a `Date`; an invalid date has none. */
export function dateText(value: Date): string {
  if (Number.isNaN(value.getTime())) {
    throw new DbException(dbError("invalid_value", "The Date is invalid"));
  }
  return value.toISOString();
}

/**
 * Wire form of an app value: Temporal values and `Date` to ISO text, `bigint`
 * to decimal text.
 */
export function encodeValue(value: unknown): unknown {
  if (typeof value !== "object" || value === null) {
    return typeof value === "bigint" ? value.toString() : value;
  }
  if (value instanceof Date) return dateText(value);
  const text = temporalText(value);
  if (text !== undefined) return text;
  if (Array.isArray(value)) return value.map(encodeValue);
  return value;
}

/** Postgres timestamps can be `infinity`; Temporal has no such value. */
function finite(value: unknown, type: string): string {
  const text = String(value);
  if (text === "infinity" || text === "-infinity") {
    throw new DbException(
      dbError("invalid_value", `${text} can't be held by a Temporal.${type}`),
    );
  }
  return text;
}

/** App form of one wire scalar for a column with `codec`. */
export function decodeScalar(codec: Codec, value: unknown): unknown {
  if (value === null || value === undefined) return value;
  switch (codec) {
    case "instant":
      return temporal().Instant.from(finite(value, "Instant"));
    case "plainDateTime":
      return temporal().PlainDateTime.from(finite(value, "PlainDateTime"));
    case "bigint":
      // SAFETY: codec columns are selected with a text cast, so they arrive as strings.
      return BigInt(value as string);
    case "string":
      return String(value);
    default: {
      const exhaustive: never = codec;
      return exhaustive;
    }
  }
}

/** App form of a wire value for a column with `codec`. */
export function decodeValue(codec: Codec, value: unknown): unknown {
  return Array.isArray(value)
    ? value.map((item) => decodeScalar(codec, item))
    : decodeScalar(codec, value);
}
