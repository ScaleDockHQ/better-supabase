import type { MoneyJson } from "better-supabase/commerce";

/** One row of the claims overview, as the page and the list route send it. */
export interface ClaimRow {
  readonly id: string;
  readonly title: string;
  readonly asset: string;
  readonly status: "draft" | "submitted" | "approved" | "denied" | "closed";
  readonly amount: MoneyJson;
  readonly claimant: string | null;
}
