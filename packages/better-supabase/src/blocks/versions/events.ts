import type {
  CollaborationEventData,
  Events,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `versions` block: type to data. */
export type VersionsEvents = {
  readonly "version.created": CollaborationEventData;
  readonly "version.restored": CollaborationEventData;
  readonly "version.deleted": CollaborationEventData;
};

/** The `versions` block's event types, for its manifest and `onBlockEvent`. */
export const versionsEvents: Events<VersionsEvents> = defineEvents({
  "version.created": event<CollaborationEventData>(),
  "version.restored": event<CollaborationEventData>(),
  "version.deleted": event<CollaborationEventData>(),
});
