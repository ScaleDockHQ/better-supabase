import type {
  AccessRequestEventData,
  Events,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `access-requests` block: type to data. */
export type AccessRequestsEvents = {
  readonly "access.requested": AccessRequestEventData;
  readonly "access.request_approved": AccessRequestEventData;
  readonly "access.ended": AccessRequestEventData;
};

/** The `access-requests` block's event types, for its manifest and `onBlockEvent`. */
export const accessRequestsEvents: Events<AccessRequestsEvents> = defineEvents({
  "access.requested": event<AccessRequestEventData>(),
  "access.request_approved": event<AccessRequestEventData>(),
  "access.ended": event<AccessRequestEventData>(),
});
