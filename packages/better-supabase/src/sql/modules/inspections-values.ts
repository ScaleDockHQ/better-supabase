// The inspections block's fixed values. This file imports nothing, so the
// client entry can read them without the SQL builders.

/** Where an audit programme stands. */
export const INSPECTION_PROGRAM_STATUSES = [
  "draft",
  "approved",
  "closed",
] as const;

/** Where an inspection stands. */
export const INSPECTION_STATUSES = [
  "planned",
  "in_progress",
  "reporting",
  "closed",
  "canceled",
] as const;

/** What a member does on an inspection. */
export const INSPECTION_MEMBER_ROLES = [
  "lead",
  "auditor",
  "observer",
  "auditee",
] as const;

/** `options.kinds` when left out. */
export const DEFAULT_INSPECTION_KINDS = [
  "internal_audit",
  "external_audit",
  "supplier_audit",
  "certification_audit",
  "inspection",
] as const;

/** `options.findingTypes` when left out. */
export const DEFAULT_INSPECTION_FINDING_TYPES = [
  "major_nonconformity",
  "minor_nonconformity",
  "observation",
  "opportunity",
  "positive",
] as const;

/** `options.caseFindingTypes` when left out: the types that need a case. */
export const DEFAULT_INSPECTION_CASE_FINDING_TYPES = [
  "major_nonconformity",
  "minor_nonconformity",
] as const;
