import type {
  CollaborationEventData,
  Events,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `trash` block: type to data. */
export type TrashEvents = {
  readonly "subject.trashed": CollaborationEventData;
  readonly "subject.restored": CollaborationEventData;
  readonly "subject.purged": CollaborationEventData;
};

/** The `trash` block's event types, for its manifest and `onBlockEvent`. */
export const trashEvents: Events<TrashEvents> = defineEvents({
  "subject.trashed": event<CollaborationEventData>(),
  "subject.restored": event<CollaborationEventData>(),
  "subject.purged": event<CollaborationEventData>(),
});
