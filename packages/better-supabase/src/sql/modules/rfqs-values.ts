// The rfqs block's fixed values. This file imports nothing, so the client entry
// can read them without the SQL builders.

/** Where a request for quotation stands. */
export const RFQ_STATUSES = [
  "draft",
  "open",
  "closed",
  "awarded",
  "cancelled",
] as const;

/** Where an invited supplier stands on one request. */
export const RFQ_SUPPLIER_STATUSES = ["invited", "declined", "quoted"] as const;

/** Where a supplier's quote stands. */
export const RFQ_QUOTE_STATUSES = [
  "submitted",
  "withdrawn",
  "awarded",
  "rejected",
] as const;
