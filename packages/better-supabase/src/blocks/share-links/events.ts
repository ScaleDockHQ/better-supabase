import type {
  SaasEventData,
  SaasSubjectEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `share-links` block: type to data. */
export type ShareLinksEvents = {
  readonly "share_link.created": SaasSubjectEventData;
  readonly "share_link.revoked": SaasEventData;
  readonly "subject.viewed": SaasSubjectEventData;
};

/** The `share-links` block's event types, for its manifest and `onBlockEvent`. */
export const shareLinksEvents: Events<ShareLinksEvents> = defineEvents({
  "share_link.created": event<SaasSubjectEventData>(),
  "share_link.revoked": event<SaasEventData>(),
  "subject.viewed": event<SaasSubjectEventData>(),
});
