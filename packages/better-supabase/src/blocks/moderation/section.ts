import type { Section } from "../sections.ts";
import type { Moderation, ModerationItemDetail } from "./moderation.ts";

import { defineSection } from "../sections.ts";

/** A record's moderation: its status, reports and log, for moderators. */
export const moderationSection: Section<
  Moderation,
  ModerationItemDetail | null
> = defineSection({
  permissions: { read: "read", write: "manage" },
  module: "moderation",
  load: (client: Moderation, subject) => client.item(subject),
  events: ["moderation_report.created", "moderation_item.decided"],
});
