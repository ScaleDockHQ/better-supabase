import type {
  EngagementEventData,
  EngagementRecordingEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `engagements` block: type to data. */
export type ActivitiesEvents = {
  readonly "engagement.logged": EngagementEventData;
  readonly "engagement.updated": EngagementEventData;
  readonly "engagement.completed": EngagementEventData;
  readonly "engagement.deleted": EngagementEventData;
  /** A recording was attached (`options.recordings`). */
  readonly "engagement.recorded": EngagementRecordingEventData;
  /** A recording's transcript was saved. */
  readonly "engagement.transcribed": EngagementRecordingEventData;
  /** The engagement's notes were saved. */
  readonly "engagement.summarized": EngagementEventData;
};

/** The `engagements` block's event types, for its manifest and `onBlockEvent`. */
export const activitiesEvents: Events<ActivitiesEvents> = defineEvents({
  "engagement.logged": event<EngagementEventData>(),
  "engagement.updated": event<EngagementEventData>(),
  "engagement.completed": event<EngagementEventData>(),
  "engagement.deleted": event<EngagementEventData>(),
  "engagement.recorded": event<EngagementRecordingEventData>(),
  "engagement.transcribed": event<EngagementRecordingEventData>(),
  "engagement.summarized": event<EngagementEventData>(),
});
