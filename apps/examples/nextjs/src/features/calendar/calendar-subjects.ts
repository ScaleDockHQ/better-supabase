/** The subject type the calendar mirrors each event into for reminders. */
export const EVENT_SUBJECT = "calendar_event";

/** The offsets a reminder can take, in minutes before the event. */
export const REMINDER_OFFSETS = [0, 15, 60, 1440] as const;

export type ReminderOffset = (typeof REMINDER_OFFSETS)[number];
