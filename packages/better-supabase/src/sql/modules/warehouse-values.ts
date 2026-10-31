// The warehouse block's fixed values. This file imports nothing, so the
// client entry can read them without the SQL builders.

/** Where a pick wave stands. */
export const PICK_WAVE_STATUSES = [
  "draft",
  "released",
  "completed",
  "cancelled",
] as const;

/** Where one pick list stands. */
export const PICK_LIST_STATUSES = ["open", "picked", "cancelled"] as const;

/** Where one pick line stands: short means less was found than asked for. */
export const PICK_LINE_STATUSES = [
  "open",
  "picked",
  "short",
  "cancelled",
] as const;
