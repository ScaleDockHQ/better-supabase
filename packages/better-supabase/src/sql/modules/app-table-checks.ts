import type { AppColumnConfig } from "../../config/types/app-tables.ts";

import { FIELD_FORMATS } from "../../core/contracts/field-formats.ts";
import { sqlString } from "../../core/template.ts";
import { formatConditions } from "../format-checks.ts";

/** A value of each checked text format that passes its check. */
const TEXT_SAMPLES: Partial<Record<string, string>> = {
  email: "'test@example.com'",
  url: "'https://example.com'",
  phone_e164: "'+31201234567'",
  bsn: "'111222333'",
  iban: "'NL91ABNA0417164300'",
};

/**
 * The conditions of a column's check on the `ident` expression: its format,
 * options and bounds.
 */
export function constraintChecks(
  column: AppColumnConfig,
  ident: string,
): string[] {
  const conditions: string[] = [];

  // A domain carries the format's pattern and bounds.
  const format =
    column.format === undefined || column.domain !== undefined
      ? undefined
      : FIELD_FORMATS[column.format];

  if (format !== undefined && column.format !== undefined) {
    conditions.push(...formatConditions(column.format, ident, "public"));
  }

  if (column.options !== undefined) {
    const list = column.options.map((option) => sqlString(option)).join(", ");

    conditions.push(
      column.type === "text[]"
        ? `${ident} <@ array[${list}]::text[]`
        : `${ident} in (${list})`,
    );
  }

  const min = column.min ?? format?.bounds?.[0];
  const max = column.max ?? format?.bounds?.[1];
  const measured = column.type === "text" ? `char_length(${ident})` : ident;

  if (min !== undefined) {
    conditions.push(`${measured} >= ${String(min)}`);
  }

  if (max !== undefined) {
    conditions.push(`${measured} <= ${String(max)}`);
  }

  return conditions;
}

/**
 * A literal that meets a required column's type, options, format and bounds,
 * for the row the read test inserts. `null` when the column needs no value
 * (nullable, defaulted or an identity); `undefined` when no literal can stand
 * in for it (a reference, which needs a parent row).
 */
export function sampleValue(
  column: AppColumnConfig,
): string | null | undefined {
  if (
    column.nullable !== false ||
    column.default !== undefined ||
    column.identity === true
  ) {
    return null;
  }

  if (column.references !== undefined) {
    return undefined;
  }

  const first = column.options?.[0];

  if (first !== undefined) {
    return column.type === "text[]"
      ? `array[${sqlString(first)}]::text[]`
      : sqlString(first);
  }

  const format =
    column.format === undefined ? undefined : FIELD_FORMATS[column.format];

  const low = column.min ?? format?.bounds?.[0];

  switch (column.type) {
    case "text": {
      const sample =
        column.format === undefined ? undefined : TEXT_SAMPLES[column.format];

      if (sample !== undefined) {
        return sample;
      }

      return `repeat('x', ${String(Math.max(low ?? 1, 1))})`;
    }

    case "integer":
    case "bigint":
    case "numeric": {
      return String(low ?? 0);
    }

    case "uuid": {
      return "gen_random_uuid()";
    }

    case "boolean": {
      return "false";
    }

    case "timestamptz": {
      return "now()";
    }

    case "date": {
      return "current_date";
    }

    case "jsonb": {
      return "'{}'::jsonb";
    }

    case "text[]": {
      return "array[]::text[]";
    }

    default: {
      const never: never = column.type;

      throw new TypeError(`Unknown app column type "${String(never)}"`);
    }
  }
}
