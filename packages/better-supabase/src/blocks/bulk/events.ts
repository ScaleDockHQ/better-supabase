import type { Events, SaasEventData } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `bulk` block: type to data. */
export type BulkEvents = {
  readonly "bulk_run.completed": SaasEventData;
};

/** The `bulk` block's event types, for its manifest and `onBlockEvent`. */
export const bulkEvents: Events<BulkEvents> = defineEvents({
  "bulk_run.completed": event<SaasEventData>(),
});
