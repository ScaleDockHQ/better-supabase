import type { DriveEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `drive` block: type to data. */
export type DriveEvents = {
  readonly "drive_node.created": DriveEventData;
  readonly "drive_node.renamed": DriveEventData;
  readonly "drive_node.moved": DriveEventData;
  readonly "drive_node.shared": DriveEventData;
  readonly "drive_node.unshared": DriveEventData;
  readonly "drive_node.purged": DriveEventData;
  readonly "drive_node.document_saved": DriveEventData;
  readonly "drive_node.submitted": DriveEventData;
  readonly "drive_node.released": DriveEventData;
  readonly "drive_node.obsoleted": DriveEventData;
  readonly "drive_node.reviewed": DriveEventData;
  readonly "drive_node.review_requested": DriveEventData;
  readonly "drive_node.hold_placed": DriveEventData;
  readonly "drive_node.hold_released": DriveEventData;
  readonly "drive_node.locked": DriveEventData;
  readonly "drive_node.unlocked": DriveEventData;
  readonly "drive_node.download_blocked_changed": DriveEventData;
  readonly "drive.download_blocked_changed": DriveEventData;
  readonly "drive.created": DriveEventData;
  readonly "drive.renamed": DriveEventData;
  readonly "drive.deleted": DriveEventData;
  readonly "drive.shared": DriveEventData;
  readonly "drive.unshared": DriveEventData;
  readonly "drive_node.ownership_transferred": DriveEventData;
  readonly "drive.ownership_transferred": DriveEventData;
  readonly "drive.connection_created": DriveEventData;
  readonly "drive.connection_removed": DriveEventData;
};

/** The `drive` block's event types, for its manifest and `onBlockEvent`. */
export const driveEvents: Events<DriveEvents> = defineEvents({
  "drive_node.created": event<DriveEventData>(),
  "drive_node.renamed": event<DriveEventData>(),
  "drive_node.moved": event<DriveEventData>(),
  "drive_node.shared": event<DriveEventData>(),
  "drive_node.unshared": event<DriveEventData>(),
  "drive_node.purged": event<DriveEventData>(),
  "drive_node.document_saved": event<DriveEventData>(),
  "drive_node.submitted": event<DriveEventData>(),
  "drive_node.released": event<DriveEventData>(),
  "drive_node.obsoleted": event<DriveEventData>(),
  "drive_node.reviewed": event<DriveEventData>(),
  "drive_node.review_requested": event<DriveEventData>(),
  "drive_node.hold_placed": event<DriveEventData>(),
  "drive_node.hold_released": event<DriveEventData>(),
  "drive_node.locked": event<DriveEventData>(),
  "drive_node.unlocked": event<DriveEventData>(),
  "drive_node.download_blocked_changed": event<DriveEventData>(),
  "drive.download_blocked_changed": event<DriveEventData>(),
  "drive.created": event<DriveEventData>(),
  "drive.renamed": event<DriveEventData>(),
  "drive.deleted": event<DriveEventData>(),
  "drive.shared": event<DriveEventData>(),
  "drive.unshared": event<DriveEventData>(),
  "drive_node.ownership_transferred": event<DriveEventData>(),
  "drive.ownership_transferred": event<DriveEventData>(),
  "drive.connection_created": event<DriveEventData>(),
  "drive.connection_removed": event<DriveEventData>(),
});
