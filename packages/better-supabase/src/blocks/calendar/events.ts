import type { Events, SchedulingEventData } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `calendar` block: type to data. */
export type CalendarEvents = {
  readonly "calendar.created": SchedulingEventData;
  readonly "calendar_event.created": SchedulingEventData;
  readonly "calendar_event.updated": SchedulingEventData;
  readonly "calendar_event.deleted": SchedulingEventData;
};

/** The `calendar` block's event types, for its manifest and `onBlockEvent`. */
export const calendarEvents: Events<CalendarEvents> = defineEvents({
  "calendar.created": event<SchedulingEventData>(),
  "calendar_event.created": event<SchedulingEventData>(),
  "calendar_event.updated": event<SchedulingEventData>(),
  "calendar_event.deleted": event<SchedulingEventData>(),
});
