import type { EngagementEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `engagements` block: type to data. */
export type EngagementsEvents = {
  readonly "engagement.logged": EngagementEventData;
  readonly "engagement.updated": EngagementEventData;
  readonly "engagement.completed": EngagementEventData;
  readonly "engagement.deleted": EngagementEventData;
};

/** The `engagements` block's event types, for its manifest and `onBlockEvent`. */
export const engagementsEvents: Events<EngagementsEvents> = defineEvents({
  "engagement.logged": event<EngagementEventData>(),
  "engagement.updated": event<EngagementEventData>(),
  "engagement.completed": event<EngagementEventData>(),
  "engagement.deleted": event<EngagementEventData>(),
});
