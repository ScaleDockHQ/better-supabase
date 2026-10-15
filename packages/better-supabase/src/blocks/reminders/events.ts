import type { SaasSubjectEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `reminders` block: type to data. */
export type RemindersEvents = {
  readonly "reminder.sent": SaasSubjectEventData;
};

/** The `reminders` block's event types, for its manifest and `onBlockEvent`. */
export const remindersEvents: Events<RemindersEvents> = defineEvents({
  "reminder.sent": event<SaasSubjectEventData>(),
});
