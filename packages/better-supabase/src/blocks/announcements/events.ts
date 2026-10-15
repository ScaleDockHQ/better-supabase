import type { AnnouncementEventData, Events } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `announcements` block: type to data. */
export type AnnouncementsEvents = {
  readonly "announcement.saved": AnnouncementEventData;
  readonly "announcement.deleted": AnnouncementEventData;
};

/** The `announcements` block's event types, for its manifest and `onBlockEvent`. */
export const announcementsEvents: Events<AnnouncementsEvents> = defineEvents({
  "announcement.saved": event<AnnouncementEventData>(),
  "announcement.deleted": event<AnnouncementEventData>(),
});
