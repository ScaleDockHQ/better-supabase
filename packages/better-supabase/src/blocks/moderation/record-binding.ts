import type { RecordBinding } from "../record-bindings.ts";
import type { Moderation, ModerationItemDetail } from "./moderation.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/** A record's moderation: its status, reports and log, for moderators. */
export const moderationBinding: RecordBinding<
  Moderation,
  ModerationItemDetail | null
> = defineRecordBinding({
  permissions: { read: "read", write: "manage" },
  module: "moderation",
  load: (client: Moderation, subject) => client.item(subject),
  events: ["moderation_report.created", "moderation_item.decided"],
});
