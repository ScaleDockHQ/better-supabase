// The commissions block's fixed values. This file imports nothing, so the
// client entry can read them without the SQL builders.

/** How a plan turns a sale into a commission. */
export const COMMISSION_PLAN_KINDS = ["flat", "tiered"] as const;

/** Where one accrued commission stands. */
export const COMMISSION_STATUSES = ["accrued", "reversed"] as const;

/** Where a seller's statement for a period stands. */
export const COMMISSION_STATEMENT_STATUSES = [
  "open",
  "finalized",
  "paid",
] as const;

/** The period kind the block contributes to the `periods` block. */
export const COMMISSION_PERIOD_KIND = "commission_period";
