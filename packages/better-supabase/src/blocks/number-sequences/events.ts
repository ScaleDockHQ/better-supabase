import type { Events, SaasEventData } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `number-sequences` block: type to data. */
export type NumberSequencesEvents = {
  readonly "number.assigned": SaasEventData;
};

/** The `number-sequences` block's event types, for its manifest and `onBlockEvent`. */
export const numberSequencesEvents: Events<NumberSequencesEvents> =
  defineEvents({
    "number.assigned": event<SaasEventData>(),
  });
