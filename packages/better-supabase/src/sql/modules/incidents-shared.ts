/** The keys the incident reads return next to the extra columns. */
export const INCIDENT_RESERVED = [
  "fields",
  "updates",
  "impacts",
  "postmortem",
] as const;

export const INCIDENT_SEVERITIES = ["sev1", "sev2", "sev3", "sev4"] as const;

export const INCIDENT_STATUSES = [
  "investigating",
  "identified",
  "monitoring",
  "resolved",
] as const;

/** Component statuses, least to most severe. */
export const COMPONENT_STATUSES = [
  "operational",
  "maintenance",
  "degraded",
  "partial_outage",
  "major_outage",
] as const;
