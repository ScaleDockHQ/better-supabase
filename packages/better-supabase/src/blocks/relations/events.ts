import type { Events, SaasSubjectEventData } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `relations` block: type to data. */
export type RelationsEvents = {
  readonly "subject.linked": SaasSubjectEventData;
  readonly "subject.unlinked": SaasSubjectEventData;
};

/** The `relations` block's event types, for its manifest and `onBlockEvent`. */
export const relationsEvents: Events<RelationsEvents> = defineEvents({
  "subject.linked": event<SaasSubjectEventData>(),
  "subject.unlinked": event<SaasSubjectEventData>(),
});
