import type {
  CollaborationEventData,
  Events,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

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
