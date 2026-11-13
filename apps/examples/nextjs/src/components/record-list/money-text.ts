import type { MoneyJson } from "better-supabase/commerce";

import { formatMoney, moneyFromJson } from "better-supabase/commerce";

import type { BlockColumn, BlockRow } from "./block-list-view";

/** A row as a loader builds it: a `money` column holds a `MoneyJson`. */
export type BlockRowInput = { readonly id: string } & Readonly<
  Record<string, string | number | boolean | MoneyJson | null>
>;

/** A `MoneyJson` in `locale`, or an empty string for a value that is not one. */
export function moneyText(
  value: BlockRowInput[string],
  locale: string,
): string {
  try {
    return value === null ? "" : formatMoney(moneyFromJson(value), locale);
  } catch {
    return "";
  }
}

/**
 * The row with each `money` column formatted for `locale`. It runs on the
 * server, so the client list view does not ship the money code.
 */
export function withMoneyCells(
  row: BlockRowInput,
  columns: readonly BlockColumn[],
  locale: string,
): BlockRow {
  const cells: Record<string, string | number | boolean | null> = {};

  for (const [key, value] of Object.entries(row)) {
    const money = columns.some(
      (column) => column.kind === "money" && column.key === key,
    );

    // SAFETY: a column that is not `money` never holds a `MoneyJson`.
    cells[key] = money ? moneyText(value, locale) : (value as BlockRow[string]);
  }

  // SAFETY: `id` is a string in the input and copied unchanged.
  return cells as BlockRow;
}
