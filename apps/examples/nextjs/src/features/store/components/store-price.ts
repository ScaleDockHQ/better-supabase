import { formatMoney, money } from "better-supabase/commerce";

import { SHOP_CURRENCY } from "@/features/shop/shop-currency";

/** A minor-unit amount from the store reads, as text in the visitor's locale. */
export function priceText(amount: string, locale: string): string {
  return formatMoney(money(BigInt(amount), SHOP_CURRENCY), locale);
}
