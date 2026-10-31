// The tills block's fixed values. This file imports nothing, so the client entry
// can read them without the SQL builders.

/** Where a till session stands. */
export const TILL_SESSION_STATUSES = ["open", "closed"] as const;

/**
 * What a cash movement is: cash taken or given back for a sale, or cash put in
 * or taken out.
 */
export const TILL_MOVEMENT_KINDS = [
  "cash_sale",
  "cash_refund",
  "cash_in",
  "cash_out",
] as const;

/** The movement kinds that add cash to the drawer. */
export const TILL_MOVEMENT_INFLOWS = ["cash_sale", "cash_in"] as const;

/** Where a cash deposit stands. */
export const TILL_DEPOSIT_STATUSES = ["pending", "reconciled"] as const;
