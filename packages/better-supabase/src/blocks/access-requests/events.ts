import type {
  AccessRequestEventData,
  EmergencyAccessEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `access-requests` block: type to data. */
export type AccessRequestsEvents = {
  readonly "access.requested": AccessRequestEventData;
  readonly "access.request_approved": AccessRequestEventData;
  readonly "access.ended": AccessRequestEventData;
  readonly "access_request.emergency_opened": EmergencyAccessEventData;
  readonly "access_request.emergency_reviewed": EmergencyAccessEventData;
};

/**
 * The `access-requests` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const accessRequestsEvents: Events<AccessRequestsEvents> = defineEvents({
  "access.requested": event<AccessRequestEventData>(),
  "access.request_approved": event<AccessRequestEventData>(),
  "access.ended": event<AccessRequestEventData>(),
  "access_request.emergency_opened": event<EmergencyAccessEventData>(),
  "access_request.emergency_reviewed": event<EmergencyAccessEventData>(),
});
