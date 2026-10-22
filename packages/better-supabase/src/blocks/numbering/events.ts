import type { SaasEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `numbering` block: type to data. */
export type NumberingEvents = { readonly "number.assigned": SaasEventData };

/** The `numbering` block's event types, for its manifest and `onBlockEvent`. */
export const numberingEvents: Events<NumberingEvents> = defineEvents({
  "number.assigned": event<SaasEventData>(),
});
