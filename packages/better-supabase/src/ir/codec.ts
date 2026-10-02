import type { Codec } from "../schema/types.ts";
import type { Measure, Selection } from "./types.ts";

import { temporal } from "../core/temporal-required.ts";
import { temporalText } from "../core/temporal.ts";

/** Wire form of an app value: Temporal values to ISO text, `bigint` to decimal text. */
export function encodeValue(value: unknown): unknown {
  if (typeof value === "bigint") return value.toString();
  const text = temporalText(value);
  if (text !== undefined) return text;
  if (Array.isArray(value)) return value.map(encodeValue);
  return value;
}

function decodeScalar(codec: Codec, value: unknown): unknown {
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

function decode(codec: Codec, value: unknown): unknown {
  return Array.isArray(value)
    ? value.map((item) => decodeScalar(codec, item))
    : decodeScalar(codec, value);
}

/** Whether decoding `selection` changes anything, so plain reads skip the walk. */
export function needsDecoding(selection: Selection): boolean {
  return (
    selection.aggregate !== undefined ||
    selection.columns.some((column) => column.codec !== undefined) ||
    selection.includes.some(
      (include) =>
        include.count !== undefined ||
        include.aggregate !== undefined ||
        needsDecoding(include.selection),
    )
  );
}

/** PostgREST returns `[{ count }]` for a `(count)` embed; SQL returns the number. */
function countOf(value: unknown): number {
  if (Array.isArray(value)) {
    // SAFETY: a count embed is a list of rows with a count field; a missing
    // field reads as 0.
    const first = value[0] as { count?: unknown } | undefined;
    return Number(first?.count ?? 0);
  }
  return Number(value ?? 0);
}

function measureOf(measure: Measure, value: unknown): unknown {
  if (value === undefined || value === null) return null;
  return measure.codec ? decodeScalar(measure.codec, value) : value;
}

/** Adds `value` under `row[key][name]`, next to what is already there. */
function fold(
  row: Record<string, unknown>,
  key: string,
  name: string,
  value: unknown,
): void {
  // SAFETY: aggregate fields are only written by this function, as objects.
  const existing = (row[key] ?? {}) as Record<string, unknown>;
  row[key] = { ...existing, [name]: value };
}

function decodeRow(
  selection: Selection,
  row: Record<string, unknown>,
): Record<string, unknown> {
  const out = { ...row };
  for (const column of selection.columns) {
    if (column.codec && column.alias in out)
      out[column.alias] = decode(column.codec, out[column.alias]);
  }
  if (selection.aggregate) {
    if (selection.aggregate.count) out["_count"] = countOf(out["_count"]);
    for (const measure of selection.aggregate.measures) {
      const value = out[measure.key];
      delete out[measure.key];
      fold(out, `_${measure.fn}`, measure.alias, measureOf(measure, value));
    }
  }
  for (const include of selection.includes) {
    const value = out[include.alias];
    if (include.count !== undefined) {
      if (!(include.alias in out)) continue;
      delete out[include.alias];
      fold(out, "_count", include.count, countOf(value));
      continue;
    }
    if (include.aggregate !== undefined) {
      if (!(include.alias in out)) continue;
      delete out[include.alias];
      // PostgREST returns `[{ amount }]` for an aggregate embed; SQL the object.
      // SAFETY: an aggregate embed is an object of measures, or a list holding one.
      const inner = (Array.isArray(value) ? value[0] : value) as
        | Record<string, unknown>
        | null
        | undefined;
      const measures: Record<string, unknown> = {};
      for (const measure of include.selection.aggregate?.measures ?? []) {
        measures[measure.alias] = measureOf(measure, inner?.[measure.key]);
      }
      fold(out, `_${include.aggregate.fn}`, include.aggregate.name, measures);
      continue;
    }
    if (Array.isArray(value)) {
      out[include.alias] = value.map((item: Record<string, unknown>) =>
        decodeRow(include.selection, item),
      );
    } else if (value && typeof value === "object") {
      // SAFETY: the check above narrows value to a non-null object, which is an embedded row.
      out[include.alias] = decodeRow(
        include.selection,
        value as Record<string, unknown>,
      );
    }
  }
  return out;
}

/** Applies column codecs to returned rows, including embedded relations. */
export function decodeRows(
  selection: Selection | undefined,
  rows: readonly Record<string, unknown>[],
): Record<string, unknown>[] {
  if (!selection || !needsDecoding(selection)) {
    // SAFETY: without codecs to apply, the rows are already in their decoded shape.
    return rows as never;
  }
  return rows.map((row) => decodeRow(selection, row));
}
