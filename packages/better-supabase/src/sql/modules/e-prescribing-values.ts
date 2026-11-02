// The e-prescribing block's fixed values. This file imports nothing, so the
// client entry can read them without the SQL builders.

/** Where a prescription stands. Each state follows the one before it. */
export const PRESCRIPTION_STATUSES = [
  "draft",
  "signed",
  "sent",
  "dispensed",
  "cancelled",
] as const;
