// The referrals block's fixed values. This file imports nothing, so the client
// entry can read them without the SQL builders.

/** Where a referral stands: attributed at signup, qualified, then rewarded. */
export const REFERRAL_STATUSES = [
  "attributed",
  "qualified",
  "rewarded",
  "void",
] as const;
