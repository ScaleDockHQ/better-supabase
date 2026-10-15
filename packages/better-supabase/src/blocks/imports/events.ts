import type { Events, SaasEventData } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `imports` block: type to data. */
export type ImportsEvents = {
  readonly "import.completed": SaasEventData;
  readonly "import.failed": SaasEventData;
};

/** The `imports` block's event types, for its manifest and `onBlockEvent`. */
export const importsEvents: Events<ImportsEvents> = defineEvents({
  "import.completed": event<SaasEventData>(),
  "import.failed": event<SaasEventData>(),
});
