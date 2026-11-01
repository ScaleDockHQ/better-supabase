// The appraisals block's fixed values. This file imports nothing, so the
// client entry can read them without the SQL builders.

/** Where a review cycle stands. */
export const APPRAISAL_CYCLE_STATUSES = ["draft", "open", "closed"] as const;

/** Where one person's appraisal in a cycle stands. */
export const APPRAISAL_STATUSES = [
  "pending",
  "reviewed",
  "calibrated",
  "awaiting_signoff",
  "signed_off",
] as const;

/** Who writes a review. */
export const APPRAISAL_REVIEW_KINDS = ["self", "peer", "manager"] as const;

/**
 * Who learns which peer reviewer wrote a review: `none` shows reviewers to
 * everyone who sees the review, `subject` hides them from the appraised person
 * and `all` shows a peer reviewer only to that reviewer (and the service
 * role).
 */
export const APPRAISAL_ANONYMITY = ["none", "subject", "all"] as const;
