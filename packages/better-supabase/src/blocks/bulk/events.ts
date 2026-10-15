import type { SaasEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `bulk` block: type to data. */
export type BulkEvents = {
  readonly "bulk_run.completed": SaasEventData;
};

/** The `bulk` block's event types, for its manifest and `onBlockEvent`. */
export const bulkEvents: Events<BulkEvents> = defineEvents({
  "bulk_run.completed": event<SaasEventData>(),
});
