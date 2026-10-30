import type {
  EngagementAmendedEventData,
  EngagementErrorMarkedEventData,
  EngagementEventData,
  EngagementRecordingEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `engagements` block: type to data. */
export type ActivitiesEvents = {
  readonly "activity.logged": EngagementEventData;
  readonly "activity.updated": EngagementEventData;
  readonly "activity.completed": EngagementEventData;
  readonly "activity.deleted": EngagementEventData;
  /** A recording was attached (`options.recordings`). */
  readonly "activity.recorded": EngagementRecordingEventData;
  /** A recording's transcript was saved. */
  readonly "activity.transcribed": EngagementRecordingEventData;
  /** The engagement's notes were saved. */
  readonly "activity.summarized": EngagementEventData;
  /** An addendum was added to an engagement. */
  readonly "activity.amended": EngagementAmendedEventData;
  /** An engagement was flagged as entered in error. */
  readonly "activity.error_marked": EngagementErrorMarkedEventData;
};

/** The `engagements` block's event types, for its manifest and `onBlockEvent`. */
export const activitiesEvents: Events<ActivitiesEvents> = defineEvents({
  "activity.logged": event<EngagementEventData>(),
  "activity.updated": event<EngagementEventData>(),
  "activity.completed": event<EngagementEventData>(),
  "activity.deleted": event<EngagementEventData>(),
  "activity.recorded": event<EngagementRecordingEventData>(),
  "activity.transcribed": event<EngagementRecordingEventData>(),
  "activity.summarized": event<EngagementEventData>(),
  "activity.amended": event<EngagementAmendedEventData>(),
  "activity.error_marked": event<EngagementErrorMarkedEventData>(),
});
