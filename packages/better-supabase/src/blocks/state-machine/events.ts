import type { SaasSubjectEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `state-machine` block: type to data. */
export type StateMachineEvents = {
  readonly "status.changed": SaasSubjectEventData;
  readonly "status.paused": SaasSubjectEventData;
  readonly "status.resumed": SaasSubjectEventData;
  readonly "status.flagged": SaasSubjectEventData;
};

/** The `state-machine` block's event types, for its manifest and `onBlockEvent`. */
export const stateMachineEvents: Events<StateMachineEvents> = defineEvents({
  "status.changed": event<SaasSubjectEventData>(),
  "status.paused": event<SaasSubjectEventData>(),
  "status.resumed": event<SaasSubjectEventData>(),
  "status.flagged": event<SaasSubjectEventData>(),
});
