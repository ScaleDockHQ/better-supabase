/** The keys the contract reads return next to the extra columns. */
export const CONTRACT_RESERVED = ["fields"] as const;

export const CONTRACT_STATUSES = [
  "draft",
  "in_review",
  "out_for_signature",
  "active",
  "expired",
  "terminated",
] as const;
