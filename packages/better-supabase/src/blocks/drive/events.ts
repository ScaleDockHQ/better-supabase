import type { DriveEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `drive` block: type to data. */
export type DriveEvents = {
  readonly "drive.node_created": DriveEventData;
  readonly "drive.node_renamed": DriveEventData;
  readonly "drive.node_moved": DriveEventData;
  readonly "drive.node_shared": DriveEventData;
  readonly "drive.node_unshared": DriveEventData;
  readonly "drive.node_purged": DriveEventData;
  readonly "drive.node_document_saved": DriveEventData;
  readonly "drive.node_submitted": DriveEventData;
  readonly "drive.node_released": DriveEventData;
  readonly "drive.node_obsoleted": DriveEventData;
  readonly "drive.node_reviewed": DriveEventData;
  readonly "drive.node_review_requested": DriveEventData;
  readonly "drive.node_hold_placed": DriveEventData;
  readonly "drive.node_hold_released": DriveEventData;
  readonly "drive.node_locked": DriveEventData;
  readonly "drive.node_unlocked": DriveEventData;
  readonly "drive.node_download_blocked_changed": DriveEventData;
  readonly "drive.download_blocked_changed": DriveEventData;
  readonly "drive.created": DriveEventData;
  readonly "drive.renamed": DriveEventData;
  readonly "drive.deleted": DriveEventData;
  readonly "drive.shared": DriveEventData;
  readonly "drive.unshared": DriveEventData;
  readonly "drive.node_ownership_transferred": DriveEventData;
  readonly "drive.ownership_transferred": DriveEventData;
  readonly "drive.connection_created": DriveEventData;
  readonly "drive.connection_removed": DriveEventData;
};

/** The `drive` block's event types, for its manifest and `onBlockEvent`. */
export const driveEvents: Events<DriveEvents> = defineEvents({
  "drive.node_created": event<DriveEventData>(),
  "drive.node_renamed": event<DriveEventData>(),
  "drive.node_moved": event<DriveEventData>(),
  "drive.node_shared": event<DriveEventData>(),
  "drive.node_unshared": event<DriveEventData>(),
  "drive.node_purged": event<DriveEventData>(),
  "drive.node_document_saved": event<DriveEventData>(),
  "drive.node_submitted": event<DriveEventData>(),
  "drive.node_released": event<DriveEventData>(),
  "drive.node_obsoleted": event<DriveEventData>(),
  "drive.node_reviewed": event<DriveEventData>(),
  "drive.node_review_requested": event<DriveEventData>(),
  "drive.node_hold_placed": event<DriveEventData>(),
  "drive.node_hold_released": event<DriveEventData>(),
  "drive.node_locked": event<DriveEventData>(),
  "drive.node_unlocked": event<DriveEventData>(),
  "drive.node_download_blocked_changed": event<DriveEventData>(),
  "drive.download_blocked_changed": event<DriveEventData>(),
  "drive.created": event<DriveEventData>(),
  "drive.renamed": event<DriveEventData>(),
  "drive.deleted": event<DriveEventData>(),
  "drive.shared": event<DriveEventData>(),
  "drive.unshared": event<DriveEventData>(),
  "drive.node_ownership_transferred": event<DriveEventData>(),
  "drive.ownership_transferred": event<DriveEventData>(),
  "drive.connection_created": event<DriveEventData>(),
  "drive.connection_removed": event<DriveEventData>(),
});
