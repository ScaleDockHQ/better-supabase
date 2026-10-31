/** Where a case stands; the stage's outcome sets it. */
export const CASE_STATUSES = ["open", "closed", "canceled"] as const;

/** What a case action does. */
export const CASE_ACTION_TYPES = [
  "containment",
  "correction",
  "corrective",
  "preventive",
  "improvement",
] as const;

/** What `case_stats` groups by. */
export const CASE_STATS_GROUPS = [
  "severity",
  "source",
  "stage",
  "kind",
  "root_cause",
] as const;

/** The hint codes `case_close_blockers` returns, in the order it checks them. */
export const CASE_BLOCKERS = [
  "CASE_ROOT_CAUSE_REQUIRED",
  "CASE_ACTIONS_REQUIRED",
  "CASE_ACTIONS_OPEN",
  "CASE_EFFECTIVENESS_REQUIRED",
  "CASE_DOCUMENTS_NOT_REVISED",
  "CASE_APPROVAL_REQUIRED",
] as const;
