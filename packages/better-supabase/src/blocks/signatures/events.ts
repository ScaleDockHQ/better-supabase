import type { SignatureEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `signatures` block: type to data. */
export type SignaturesEvents = {
  readonly "signature_request.requested": SignatureEventData;
  readonly "signature_request.signed": SignatureEventData;
  readonly "signature_request.completed": SignatureEventData;
  readonly "signature_request.declined": SignatureEventData;
  readonly "signature_request.cancelled": SignatureEventData;
};

/** The `signatures` block's event types, for its manifest and `onBlockEvent`. */
export const signaturesEvents: Events<SignaturesEvents> = defineEvents({
  "signature_request.requested": event<SignatureEventData>(),
  "signature_request.signed": event<SignatureEventData>(),
  "signature_request.completed": event<SignatureEventData>(),
  "signature_request.declined": event<SignatureEventData>(),
  "signature_request.cancelled": event<SignatureEventData>(),
});
