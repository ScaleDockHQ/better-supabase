import type { AuditRevealEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `audit` block: type to data. */
export type AuditEvents = {
  readonly "audit.revealed": AuditRevealEventData;
};

/** The `audit` block's event types, for its manifest and `onBlockEvent`. */
export const auditEvents: Events<AuditEvents> = defineEvents({
  "audit.revealed": event<AuditRevealEventData>(),
});
