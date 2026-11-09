/** The statuses a warranty claim can hold, in lifecycle order. */
export const WARRANTY_STATUSES = [
  "draft",
  "submitted",
  "approved",
  "denied",
  "closed",
] as const;

/** A warranty claim's status. */
export type WarrantyStatus = (typeof WARRANTY_STATUSES)[number];

/** The statuses `decide` may set. Closing keeps the earlier decision. */
export const WARRANTY_DECISIONS = ["approved", "denied", "closed"] as const;

/** A status `decide` may set. */
export type WarrantyDecision = (typeof WARRANTY_DECISIONS)[number];
