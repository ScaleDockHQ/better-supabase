import type { FlagEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `flags` block: type to data. */
export type FlagsEvents = {
  readonly "flag.created": FlagEventData;
  readonly "flag.updated": FlagEventData;
  readonly "flag.deleted": FlagEventData;
  readonly "flag.override_changed": FlagEventData;
};

/** The `flags` block's event types, for its manifest and `onBlockEvent`. */
export const flagsEvents: Events<FlagsEvents> = defineEvents({
  "flag.created": event<FlagEventData>(),
  "flag.updated": event<FlagEventData>(),
  "flag.deleted": event<FlagEventData>(),
  "flag.override_changed": event<FlagEventData>(),
});
