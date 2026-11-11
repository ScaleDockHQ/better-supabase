import type { MoneyJson } from "better-supabase/commerce";

/** One row of the gifts overview, as the page and the list route send it. */
export interface GiftRow {
  readonly id: string;
  readonly donor: string;
  readonly status: "pending" | "posted" | "failed" | "refunded";
  readonly amount: MoneyJson;
  readonly receivedOn: string;
  readonly hasReceipt: boolean;
}
