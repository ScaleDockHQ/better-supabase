import type {
  DocumentEventData,
  DocumentSuggestionEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `documents` block: type to data. */
export type DocumentsEvents = {
  readonly "document.created": DocumentEventData;
  readonly "document.suggested": DocumentSuggestionEventData;
  readonly "document.suggestion_accepted": DocumentSuggestionEventData;
  readonly "document.suggestion_rejected": DocumentSuggestionEventData;
};

/** The `documents` block's event types, for its manifest and `onBlockEvent`. */
export const documentsEvents: Events<DocumentsEvents> = defineEvents({
  "document.created": event<DocumentEventData>(),
  "document.suggested": event<DocumentSuggestionEventData>(),
  "document.suggestion_accepted": event<DocumentSuggestionEventData>(),
  "document.suggestion_rejected": event<DocumentSuggestionEventData>(),
});
