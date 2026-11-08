import type {
  ActivityAmendedEventData,
  ActivityErrorMarkedEventData,
  ActivityEventData,
  ActivityRecordingEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `activities` block: type to data. */
export type ActivitiesEvents = {
  readonly "activity.logged": ActivityEventData;
  readonly "activity.updated": ActivityEventData;
  readonly "activity.completed": ActivityEventData;
  readonly "activity.deleted": ActivityEventData;
  /** A recording was attached (`options.recordings`). */
  readonly "activity.recorded": ActivityRecordingEventData;
  /** A recording's transcript was saved. */
  readonly "activity.transcribed": ActivityRecordingEventData;
  /** The activity's notes were saved. */
  readonly "activity.summarized": ActivityEventData;
  /** An addendum was added to an activity. */
  readonly "activity.amended": ActivityAmendedEventData;
  /** An activity was flagged as entered in error. */
  readonly "activity.error_marked": ActivityErrorMarkedEventData;
};

/** The `activities` block's event types, for its manifest and `onBlockEvent`. */
export const activitiesEvents: Events<ActivitiesEvents> = defineEvents({
  "activity.logged": event<ActivityEventData>(),
  "activity.updated": event<ActivityEventData>(),
  "activity.completed": event<ActivityEventData>(),
  "activity.deleted": event<ActivityEventData>(),
  "activity.recorded": event<ActivityRecordingEventData>(),
  "activity.transcribed": event<ActivityRecordingEventData>(),
  "activity.summarized": event<ActivityEventData>(),
  "activity.amended": event<ActivityAmendedEventData>(),
  "activity.error_marked": event<ActivityErrorMarkedEventData>(),
});
