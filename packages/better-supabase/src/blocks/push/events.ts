import type { PushDeviceEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `push` block: type to data. */
export type PushEvents = {
  readonly "push.device_registered": PushDeviceEventData;
  readonly "push.device_unregistered": PushDeviceEventData;
};

/** The `push` block's event types, for its manifest and `onBlockEvent`. */
export const pushEvents: Events<PushEvents> = defineEvents({
  "push.device_registered": event<PushDeviceEventData>(),
  "push.device_unregistered": event<PushDeviceEventData>(),
});
