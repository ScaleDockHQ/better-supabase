// The clinical-decision-support block's fixed values. This file imports
// nothing, so the client entry can read them without the SQL builders.

/** What a rule or an alert is about. */
export const CARE_ALERT_KINDS = [
  "dose_range",
  "duplicate_therapy",
  "interaction",
  "allergy",
  "other",
] as const;

/** The rule kinds the built-in rule set evaluates in SQL. */
export const CARE_RULE_KINDS = [
  "dose_range",
  "duplicate_therapy",
  "interaction",
] as const;

/** How serious an alert is. `critical` needs a reason to override. */
export const CARE_ALERT_SEVERITIES = ["info", "warning", "critical"] as const;

/**
 * Where an alert stands. `resolved` means the engine no longer raises it;
 * `acknowledged` and `overridden` are a member's decision.
 */
export const CARE_ALERT_STATUSES = [
  "open",
  "acknowledged",
  "overridden",
  "resolved",
] as const;

/** The decisions a member can take on an open alert. */
export const CARE_ALERT_DECISIONS = ["acknowledged", "overridden"] as const;

/** The source of the alerts the built-in rule set raises. */
export const CARE_BUILT_IN_SOURCE = "built-in";
