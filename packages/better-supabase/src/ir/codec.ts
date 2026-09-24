import type { Codec } from '../schema/types.ts';
import type { Selection } from './types.ts';

/** Wire form of an app value: `Date` to ISO text, `bigint` to decimal text. */
export function encodeValue(value: unknown): unknown {
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'bigint') return value.toString();
  if (Array.isArray(value)) return value.map(encodeValue);
  return value;
}

function decodeScalar(codec: Codec, value: unknown): unknown {
  if (value === null || value === undefined) return value;
  switch (codec) {
    case 'date':
      return new Date(value as string);
    case 'bigint':
      return BigInt(value as string);
    case 'string':
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
    selection.columns.some((column) => column.codec !== undefined) ||
    selection.includes.some(
      (include) =>
        include.count !== undefined || needsDecoding(include.selection),
    )
  );
}

/** PostgREST returns `[{ count }]` for a `(count)` embed; SQL returns the number. */
function countOf(value: unknown): number {
  if (Array.isArray(value)) {
    const first = value[0] as { count?: unknown } | undefined;
    return Number(first?.count ?? 0);
  }
  return Number(value ?? 0);
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
  for (const include of selection.includes) {
    const value = out[include.alias];
    if (include.count !== undefined) {
      if (!(include.alias in out)) continue;
      delete out[include.alias];
      const counts = (out['_count'] ?? {}) as Record<string, number>;
      out['_count'] = { ...counts, [include.count]: countOf(value) };
      continue;
    }
    if (Array.isArray(value)) {
      out[include.alias] = value.map((item: Record<string, unknown>) =>
        decodeRow(include.selection, item),
      );
    } else if (value && typeof value === 'object') {
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
  if (!selection || !needsDecoding(selection)) return rows as never;
  return rows.map((row) => decodeRow(selection, row));
}
