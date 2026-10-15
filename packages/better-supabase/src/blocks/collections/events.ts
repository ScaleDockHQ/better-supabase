import type {
  CollectionEntryEventData,
  CollectionEventData,
  Events,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `collections` block: type to data. */
export type CollectionsEvents = {
  readonly "collection.created": CollectionEventData;
  readonly "collection.archived": CollectionEventData;
  readonly "collection.entry_added": CollectionEntryEventData;
  readonly "collection.entry_removed": CollectionEntryEventData;
};

/** The `collections` block's event types, for its manifest and `onBlockEvent`. */
export const collectionsEvents: Events<CollectionsEvents> = defineEvents({
  "collection.created": event<CollectionEventData>(),
  "collection.archived": event<CollectionEventData>(),
  "collection.entry_added": event<CollectionEntryEventData>(),
  "collection.entry_removed": event<CollectionEntryEventData>(),
});
