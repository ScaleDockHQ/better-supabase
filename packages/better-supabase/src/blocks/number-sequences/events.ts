import type { SaasEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `number-sequences` block: type to data. */
export type NumberSequencesEvents = {
  readonly "number.assigned": SaasEventData;
};

/** The `number-sequences` block's event types, for its manifest and `onBlockEvent`. */
export const numberSequencesEvents: Events<NumberSequencesEvents> =
  defineEvents({
    "number.assigned": event<SaasEventData>(),
  });
