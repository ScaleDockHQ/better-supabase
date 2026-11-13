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
  options: { announcements: announcementsSqlOptions },
  events: announcementsEvents,
  create: createAnnouncements,
  client: "announcements",
  category: "growth",
  entities: {
    announcement: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  description:
    "In-app announcements for everyone, tenants, roles or plans within a time window, with per-user dismissals and a Realtime broadcast when they change. Staff manage them with announcements.manage on the platform.",
  recipes: ["announcement-banner"],
});
