// The meetings block's fixed values. This file imports nothing, so the client
// entry can read them without the SQL builders.

/** Where a meeting stands. */
export const MEETING_STATUSES = [
  "planned",
  "in_progress",
  "held",
  "cancelled",
] as const;

/** What an attendee does at a meeting. */
export const MEETING_ATTENDEE_ROLES = [
  "chair",
  "secretary",
  "attendee",
  "guest",
] as const;

/** Whether an attendee was there. */
export const MEETING_ATTENDANCE = [
  "invited",
  "present",
  "absent",
  "excused",
] as const;

/** Where an agenda item stands. */
export const MEETING_AGENDA_STATUSES = ["open", "covered", "skipped"] as const;

/** Where a decision stands. */
export const MEETING_DECISION_STATUSES = [
  "proposed",
  "passed",
  "rejected",
  "deferred",
] as const;

/** `options.kinds` when left out. */
export const DEFAULT_MEETING_KINDS = [
  "meeting",
  "board",
  "management_review",
  "one_on_one",
  "toolbox_talk",
] as const;
