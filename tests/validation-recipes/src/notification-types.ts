import type { StandardSchemaV1 } from "better-supabase";
import type { SubjectEventData } from "better-supabase/events";

const subject: StandardSchemaV1<SubjectEventData> = {
  "~standard": {
    version: 1,
    vendor: "validation-recipes",
    // SAFETY: watcherSink and reminder delivery build this data from a subject event row.
    validate: (value) => ({ value: value as SubjectEventData }),
  },
};

/** The notification types the recipes send; each carries the subject it is about. */
export const NOTIFICATION_TYPES = {
  "subject.commented": subject,
  "subject.tagged": subject,
  "subject.moved": subject,
  "subject.shared": subject,
  "subject.field_changed": subject,
  "reminder.due": subject,
};
