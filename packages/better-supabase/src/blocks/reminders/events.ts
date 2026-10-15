import type { Events, SaasSubjectEventData } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `reminders` block: type to data. */
export type RemindersEvents = {
  readonly "reminder.sent": SaasSubjectEventData;
};

/** The `reminders` block's event types, for its manifest and `onBlockEvent`. */
export const remindersEvents: Events<RemindersEvents> = defineEvents({
  "reminder.sent": event<SaasSubjectEventData>(),
});
