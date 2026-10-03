import type { Measure, Selection } from "./types.ts";

import { DbException, dbError } from "../core/errors.ts";
import { decodeScalar, decodeValue } from "./wire.ts";

/** Whether decoding `selection` changes anything, so plain reads skip the walk. */
export function needsDecoding(selection: Selection): boolean {
  let needs = decodes.get(selection);
  if (needs === undefined) {
    needs = computeNeedsDecoding(selection);
    decodes.set(selection, needs);
  }
  return needs;
}

const decodes = new WeakMap<Selection, boolean>();

function computeNeedsDecoding(selection: Selection): boolean {
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

type Folded = Map<string, Record<string, unknown>>;

/** Adds `value` under `row[key][name]`, next to what is already there. */
function fold(
  row: Record<string, unknown>,
  folded: Folded,
  key: string,
  name: string,
  value: unknown,
): void {
  let target = folded.get(key);
  if (!target) {
    // SAFETY: aggregate fields are only written by this function, as objects.
    target = { ...(row[key] as Record<string, unknown> | undefined) };
    folded.set(key, target);
    row[key] = target;
  }
  target[name] = value;
}

const droppedKeys = new WeakMap<Selection, ReadonlySet<string>>();

/** Wire keys that decoding folds into `_count`, `_sum` and the rest. */
function droppedOf(selection: Selection): ReadonlySet<string> {
  let dropped = droppedKeys.get(selection);
  if (!dropped) {
    dropped = new Set([
      ...(selection.aggregate?.measures.map((measure) => measure.key) ?? []),
      ...selection.includes
        .filter(
          (include) =>
            include.count !== undefined || include.aggregate !== undefined,
        )
        .map((include) => include.alias),
    ]);
    droppedKeys.set(selection, dropped);
  }
  return dropped;
}

function decodeRow(
  selection: Selection,
  row: Record<string, unknown>,
): Record<string, unknown> {
  const dropped = droppedOf(selection);
  const out: Record<string, unknown> = {};
  for (const key in row) {
    if (!dropped.has(key) && Object.hasOwn(row, key)) out[key] = row[key];
  }
  const folded: Folded = new Map();
  for (const column of selection.columns) {
    if (!column.codec || !(column.alias in out)) continue;
    try {
      out[column.alias] = decodeValue(column.codec, out[column.alias]);
    } catch (cause) {
      if (
        !(cause instanceof DbException) ||
        cause.error.kind !== "invalid_value"
      )
        throw cause;
      throw new DbException(
        dbError("invalid_value", `${column.alias}: ${cause.error.message}`, {
          column: column.alias,
        }),
      );
    }
  }
  if (selection.aggregate) {
    if (selection.aggregate.count) out["_count"] = countOf(out["_count"]);
    for (const measure of selection.aggregate.measures) {
      const value = row[measure.key];
      fold(
        out,
        folded,
        `_${measure.fn}`,
        measure.alias,
        measureOf(measure, value),
      );
    }
  }
  for (const include of selection.includes) {
    const value = row[include.alias];
    if (include.count !== undefined) {
      if (!(include.alias in row)) continue;
      fold(out, folded, "_count", include.count, countOf(value));
      continue;
    }
    if (include.aggregate !== undefined) {
      if (!(include.alias in row)) continue;
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
      fold(
        out,
        folded,
        `_${include.aggregate.fn}`,
        include.aggregate.name,
        measures,
      );
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
  /** The caller already checked `needsDecoding(selection)`. */
  checked = false,
): Record<string, unknown>[] {
  if (!selection || (!checked && !needsDecoding(selection))) {
    // SAFETY: without codecs to apply, the rows are already in their decoded shape.
    return rows as never;
  }
  return rows.map((row) => decodeRow(selection, row));
}
