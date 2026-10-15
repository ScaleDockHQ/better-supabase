import type {
  Events,
  TimeEntryEventData,
  TimesheetEventData,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `time-tracking` block: type to data. */
export type TimeTrackingEvents = {
  readonly "time_entry.started": TimeEntryEventData;
  readonly "time_entry.recorded": TimeEntryEventData;
  readonly "time_entry.updated": TimeEntryEventData;
  readonly "time_entry.deleted": TimeEntryEventData;
  readonly "timesheet.submitted": TimesheetEventData;
  readonly "timesheet.approved": TimesheetEventData;
  readonly "timesheet.reopened": TimesheetEventData;
};

/** The `time-tracking` block's event types, for its manifest and `onBlockEvent`. */
export const timeTrackingEvents: Events<TimeTrackingEvents> = defineEvents({
  "time_entry.started": event<TimeEntryEventData>(),
  "time_entry.recorded": event<TimeEntryEventData>(),
  "time_entry.updated": event<TimeEntryEventData>(),
  "time_entry.deleted": event<TimeEntryEventData>(),
  "timesheet.submitted": event<TimesheetEventData>(),
  "timesheet.approved": event<TimesheetEventData>(),
  "timesheet.reopened": event<TimesheetEventData>(),
});
