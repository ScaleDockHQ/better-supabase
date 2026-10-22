import type { AppColumnConfig, AppColumnType } from "./types/app-tables.ts";

import { FIELD_FORMATS } from "../core/contracts/field-formats.ts";

const TEXT_LITERAL = /^'(?:[^'\\]|'')*'$/;
const INTEGER = /^-?\d{1,18}$/;
const NUMBER = /^-?\d{1,30}(?:\.\d{1,30})?$/;
const MAX_LITERAL = 200;

/** The defaults `isAppDefault` accepts, per type, as a message names them. */
const DEFAULT_EXAMPLES: Record<AppColumnType, string> = {
  text: "a 'quoted' text",
  integer: "a whole number",
  bigint: "a whole number",
  numeric: "a number",
  boolean: "true or false",
  uuid: "gen_random_uuid(), auth.uid() or a 'quoted' value",
  timestamptz: "now() or a 'quoted' value",
  date: "now() or a 'quoted' value",
  jsonb: "'{}' or '[]'",
  "text[]": "'{}'",
};

/**
 * Why `value` can't be the default of `column`, or `undefined` when it can: it
 * must be on the `isAppDefault` allowlist, one of the column's `options`, and
 * inside its bounds (`min`, `max`, or those of its format).
 */
export function appDefaultError(
  column: Pick<AppColumnConfig, "type" | "options" | "min" | "max" | "format">,
  value: string,
): string | undefined {
  const { type } = column;

  if (!isAppDefault(type, value)) {
    return `A ${type} column takes ${DEFAULT_EXAMPLES[type]} as its default.`;
  }

  const literal = TEXT_LITERAL.test(value)
    ? value.slice(1, -1).replaceAll("''", "'")
    : undefined;

  if (
    type === "text" &&
    column.options !== undefined &&
    literal !== undefined &&
    !column.options.includes(literal)
  ) {
    return `The default must be one of the options: ${column.options.join(", ")}.`;
  }

  const bounds =
    column.format === undefined
      ? undefined
      : FIELD_FORMATS[column.format].bounds;

  const min = column.min ?? bounds?.[0];
  const max = column.max ?? bounds?.[1];

  const size =
    type === "text"
      ? literal?.length
      : NUMBER.test(value)
        ? Number(value)
        : undefined;

  if (size === undefined) {
    return undefined;
  }

  const what = type === "text" ? "length" : "value";

  if (min !== undefined && size < min) {
    return `The default's ${what} is below the minimum of ${String(min)}.`;
  }

  if (max !== undefined && size > max) {
    return `The default's ${what} is above the maximum of ${String(max)}.`;
  }

  return undefined;
}

/** Whether `value` is a default `type` accepts; see `AppColumnConfig.default`. */
export function isAppDefault(type: AppColumnType, value: string): boolean {
  switch (value) {
    case "now()": {
      return type === "timestamptz" || type === "date";
    }

    case "gen_random_uuid()":
    case "auth.uid()": {
      return type === "uuid";
    }

    case "true":
    case "false": {
      return type === "boolean";
    }

    case "'{}'": {
      return type === "jsonb" || type === "text[]" || type === "text";
    }

    case "'[]'": {
      return type === "jsonb" || type === "text";
    }

    default: {
      break;
    }
  }

  if (INTEGER.test(value)) {
    return type === "integer" || type === "bigint" || type === "numeric";
  }

  if (NUMBER.test(value)) {
    return type === "numeric";
  }

  return (
    value.length <= MAX_LITERAL &&
    TEXT_LITERAL.test(value) &&
    (type === "text" ||
      type === "uuid" ||
      type === "date" ||
      type === "timestamptz")
  );
}
