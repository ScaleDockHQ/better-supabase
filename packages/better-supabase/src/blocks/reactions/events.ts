import type { CollaborationEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `reactions` block: type to data. */
export type ReactionsEvents = {
  readonly "reaction.added": CollaborationEventData;
  readonly "reaction.removed": CollaborationEventData;
};

/** The `reactions` block's event types, for its manifest and `onBlockEvent`. */
export const reactionsEvents: Events<ReactionsEvents> = defineEvents({
  "reaction.added": event<CollaborationEventData>(),
  "reaction.removed": event<CollaborationEventData>(),
});
