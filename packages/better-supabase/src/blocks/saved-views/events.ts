import type { SaasEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `saved-views` block: type to data. */
export type SavedViewsEvents = {
  readonly "saved_view.created": SaasEventData;
  readonly "saved_view.updated": SaasEventData;
  readonly "saved_view.deleted": SaasEventData;
};

/** The `saved-views` block's event types, for its manifest and `onBlockEvent`. */
export const savedViewsEvents: Events<SavedViewsEvents> = defineEvents({
  "saved_view.created": event<SaasEventData>(),
  "saved_view.updated": event<SaasEventData>(),
  "saved_view.deleted": event<SaasEventData>(),
});
