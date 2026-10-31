// The dam block's fixed values. This file imports nothing, so the client entry
// can read them without the SQL builders.

/** Where a rendition is in its life. */
export const DAM_RENDITION_STATUSES = ["pending", "ready", "failed"] as const;

/** Whether a usage right lets the file be used today. */
export const DAM_USAGE_RIGHT_STATUSES = [
  "upcoming",
  "active",
  "expired",
  "revoked",
] as const;
