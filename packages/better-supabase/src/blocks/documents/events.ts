import type { DocumentEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `documents` block: type to data. */
export type DocumentsEvents = {
  readonly "document.created": DocumentEventData;
};

/** The `documents` block's event types, for its manifest and `onBlockEvent`. */
export const documentsEvents: Events<DocumentsEvents> = defineEvents({
  "document.created": event<DocumentEventData>(),
});
