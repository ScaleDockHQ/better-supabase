import type { SlaEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `sla` block: type to data. */
export type SlaEvents = {
  readonly "sla.warned": SlaEventData;
  readonly "sla.breached": SlaEventData;
  readonly "sla.completed": SlaEventData;
};

/** The `sla` block's event types, for its manifest and `onBlockEvent`. */
export const slaEvents: Events<SlaEvents> = defineEvents({
  "sla.warned": event<SlaEventData>(),
  "sla.breached": event<SlaEventData>(),
  "sla.completed": event<SlaEventData>(),
});
