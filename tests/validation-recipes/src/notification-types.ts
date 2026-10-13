import type { StandardSchemaV1 } from "better-supabase";
import type { SubjectEventData } from "better-supabase/events";

interface ReminderDue {
  readonly reminderId: string;
  readonly occurrenceAt: string;
}

const subject: StandardSchemaV1<SubjectEventData> = {
  "~standard": {
    version: 1,
    vendor: "validation-recipes",
    // SAFETY: watcherHandler passes the data of a subject event, which carries these keys.
    validate: (value) => ({ value: value as SubjectEventData }),
  },
};

const reminderDue: StandardSchemaV1<ReminderDue> = {
  "~standard": {
    version: 1,
    vendor: "validation-recipes",
    // SAFETY: reminders.deliver sends { reminderId, occurrenceAt } for this type.
    validate: (value) => ({ value: value as ReminderDue }),
  },
};

/** The notification types the recipes send. */
export const NOTIFICATION_TYPES = {
  "subject.commented": subject,
  "subject.tagged": subject,
  "subject.moved": subject,
  "subject.shared": subject,
  "subject.field_changed": subject,
  "reminder.due": reminderDue,
};
