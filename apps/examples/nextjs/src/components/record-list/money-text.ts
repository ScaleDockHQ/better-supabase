import { formatMoney, moneyFromJson } from "better-supabase/commerce";

import type { BlockRow } from "./block-list-view";

/**
 * A `MoneyJson` cell in `locale`, or an empty string for a value that is not
 * one.
 */
export function moneyText(value: BlockRow[string], locale: string): string {
  try {
    return value === null ? "" : formatMoney(moneyFromJson(value), locale);
  } catch {
    return "";
  }
}
