import type { Codec } from "../schema/types.ts";

import { temporal } from "../core/temporal-required.ts";
import { temporalText } from "../core/temporal.ts";

/** Wire form of an app value: Temporal values to ISO text, `bigint` to decimal text. */
export function encodeValue(value: unknown): unknown {
  if (typeof value !== "object" || value === null) {
    return typeof value === "bigint" ? value.toString() : value;
  }
  const text = temporalText(value);
  if (text !== undefined) return text;
  if (Array.isArray(value)) return value.map(encodeValue);
  return value;
}

/** App form of one wire scalar for a column with `codec`. */
export function decodeScalar(codec: Codec, value: unknown): unknown {
  if (value === null || value === undefined) return value;
  switch (codec) {
    case "instant":
      return temporal().Instant.from(String(value));
    case "plainDateTime":
      return temporal().PlainDateTime.from(String(value));
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
