import type { SaasEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `imports` block: type to data. */
export type ImportsEvents = {
  readonly "import.completed": SaasEventData;
  readonly "import.failed": SaasEventData;
  /** One per entity of a run, with its counts. */
  readonly "import.entity_completed": SaasEventData;
};

/** The `imports` block's event types, for its manifest and `onBlockEvent`. */
export const importsEvents: Events<ImportsEvents> = defineEvents({
  "import.completed": event<SaasEventData>(),
  "import.failed": event<SaasEventData>(),
  "import.entity_completed": event<SaasEventData>(),
});
