export {
  type Announcement,
  type AnnouncementAudience,
  type AnnouncementInput,
  type Announcements,
  type AnnouncementSeverity,
  type AnnouncementsOptions,
  createAnnouncements,
  type ManagedAnnouncement,
} from "./announcements.ts";

export {
  dbTransport,
  rpcTransport,
  sqlTransport,
} from "../../core/block-transport.ts";

export type { BlockTransport } from "../../core/block-transport.ts";

export { createAnnouncementsController } from "./client.ts";

export type {
  AnnouncementsActions,
  AnnouncementsController,
  AnnouncementsControllerOptions,
  AnnouncementsSnapshot,
} from "./client.ts";

export { announcementsBlock } from "./manifest.ts";

export { announcementsEvents } from "./events.ts";

export type { AnnouncementsEvents } from "./events.ts";
