import type { MoneyJson } from "better-supabase/commerce";

/** One row of the lease overview, as the page and the list route send it. */
export interface LeaseRow {
  readonly id: string;
  readonly title: string;
  readonly status: "draft" | "active" | "ended" | "terminated";
  readonly startsOn: string;
  readonly endsOn: string | null;
  readonly rent: MoneyJson;
  readonly frequency: "weekly" | "monthly" | "quarterly" | "yearly";
  readonly balanceDue: MoneyJson;
}
