import type {
  AccessRequestEventData,
  EmergencyAccessEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `access-requests` block: type to data. */
export type AccessRequestsEvents = {
  readonly "access_request.requested": AccessRequestEventData;
  readonly "access_request.approved": AccessRequestEventData;
  readonly "access_request.ended": AccessRequestEventData;
  readonly "access_request.emergency_opened": EmergencyAccessEventData;
  readonly "access_request.emergency_reviewed": EmergencyAccessEventData;
};

/**
 * The `access-requests` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const accessRequestsEvents: Events<AccessRequestsEvents> = defineEvents({
  "access_request.requested": event<AccessRequestEventData>(),
  "access_request.approved": event<AccessRequestEventData>(),
  "access_request.ended": event<AccessRequestEventData>(),
  "access_request.emergency_opened": event<EmergencyAccessEventData>(),
  "access_request.emergency_reviewed": event<EmergencyAccessEventData>(),
});
