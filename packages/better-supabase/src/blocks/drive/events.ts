import type { DriveEventData, Events } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `drive` block: type to data. */
export type DriveEvents = {
  readonly "drive.node_created": DriveEventData;
  readonly "drive.node_renamed": DriveEventData;
  readonly "drive.node_moved": DriveEventData;
  readonly "drive.node_shared": DriveEventData;
  readonly "drive.node_unshared": DriveEventData;
  readonly "drive.node_purged": DriveEventData;
};

/** The `drive` block's event types, for its manifest and `onBlockEvent`. */
export const driveEvents: Events<DriveEvents> = defineEvents({
  "drive.node_created": event<DriveEventData>(),
  "drive.node_renamed": event<DriveEventData>(),
  "drive.node_moved": event<DriveEventData>(),
  "drive.node_shared": event<DriveEventData>(),
  "drive.node_unshared": event<DriveEventData>(),
  "drive.node_purged": event<DriveEventData>(),
});
