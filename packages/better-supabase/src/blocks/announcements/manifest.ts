import type { BlockOf } from "../define-block.ts";
import type { AnnouncementsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAnnouncements } from "./announcements.ts";
import { announcementsEvents } from "./events.ts";
import { announcementsSqlOptions } from "./options.ts";

/** The `announcements` block's manifest (ADR 0029). */
export const announcementsBlock: BlockOf<
  "announcements",
  typeof createAnnouncements,
  AnnouncementsEvents
> = defineBlock({
  name: "announcements",
  sql: ["announcements"],
  options: {
    announcements: announcementsSqlOptions,
  },
  events: announcementsEvents,
  create: createAnnouncements,
  client: "announcements",
  category: "operations",
});
