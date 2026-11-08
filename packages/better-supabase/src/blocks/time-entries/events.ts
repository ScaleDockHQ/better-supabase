import type {
  TimeEntryEventData,
  TimesheetEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `time-entries` block: type to data. */
export type TimeEntriesEvents = {
  readonly "time_entry.started": TimeEntryEventData;
  readonly "time_entry.recorded": TimeEntryEventData;
  readonly "time_entry.updated": TimeEntryEventData;
  readonly "time_entry.deleted": TimeEntryEventData;
  readonly "timesheet.submitted": TimesheetEventData;
  readonly "timesheet.approved": TimesheetEventData;
  readonly "timesheet.reopened": TimesheetEventData;
  /** With `options.approvals: false`: an approver rejected the week. */
  readonly "timesheet.rejected": TimesheetEventData;
};

/** The `time-entries` block's event types, for its manifest and `onBlockEvent`. */
export const timeEntriesEvents: Events<TimeEntriesEvents> = defineEvents({
  "time_entry.started": event<TimeEntryEventData>(),
  "time_entry.recorded": event<TimeEntryEventData>(),
  "time_entry.updated": event<TimeEntryEventData>(),
  "time_entry.deleted": event<TimeEntryEventData>(),
  "timesheet.submitted": event<TimesheetEventData>(),
  "timesheet.approved": event<TimesheetEventData>(),
  "timesheet.reopened": event<TimesheetEventData>(),
  "timesheet.rejected": event<TimesheetEventData>(),
});
