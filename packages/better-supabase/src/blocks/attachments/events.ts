import type {
  AttachmentEventData,
  StorageObjectEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `attachments` block: type to data. */
export type AttachmentsEvents = {
  readonly "object.uploaded": StorageObjectEventData;
  readonly "attachment.uploaded": AttachmentEventData;
  readonly "attachment.scanned": AttachmentEventData;
};

/** The `attachments` block's event types, for its manifest and `onBlockEvent`. */
export const attachmentsEvents: Events<AttachmentsEvents> = defineEvents({
  "object.uploaded": event<StorageObjectEventData>(),
  "attachment.uploaded": event<AttachmentEventData>(),
  "attachment.scanned": event<AttachmentEventData>(),
});
