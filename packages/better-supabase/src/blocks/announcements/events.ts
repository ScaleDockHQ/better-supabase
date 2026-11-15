import type { AnnouncementEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `announcements` block: type to data. */
export type AnnouncementsEvents = {
  readonly "announcement.created": AnnouncementEventData;
  readonly "announcement.updated": AnnouncementEventData;
  readonly "announcement.archived": AnnouncementEventData;
  readonly "announcement.restored": AnnouncementEventData;
  readonly "announcement.purged": AnnouncementEventData;
};

/** The `announcements` block's event types, for its manifest and `onBlockEvent`. */
export const announcementsEvents: Events<AnnouncementsEvents> = defineEvents({
  "announcement.created": event<AnnouncementEventData>(),
  "announcement.updated": event<AnnouncementEventData>(),
  "announcement.archived": event<AnnouncementEventData>(),
  "announcement.restored": event<AnnouncementEventData>(),
  "announcement.purged": event<AnnouncementEventData>(),
});
