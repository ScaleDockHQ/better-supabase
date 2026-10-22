import type { SaasEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `bulk` block: type to data. */
export type BulkActionsEvents = {
  readonly "bulk_run.completed": SaasEventData;
};

/** The `bulk` block's event types, for its manifest and `onBlockEvent`. */
export const bulkActionsEvents: Events<BulkActionsEvents> = defineEvents({
  "bulk_run.completed": event<SaasEventData>(),
});
