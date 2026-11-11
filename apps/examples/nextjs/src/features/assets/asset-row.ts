import type { MoneyJson } from "better-supabase/commerce";

/** One row of the asset register, as the page and the list route send it. */
export interface AssetRow {
  readonly id: string;
  readonly name: string;
  readonly kind: string;
  readonly tag: string | null;
  readonly serialNumber: string | null;
  readonly status: "active" | "maintenance" | "retired";
  readonly assigned: boolean;
  readonly cost: MoneyJson | null;
  readonly createdAt: string;
}
