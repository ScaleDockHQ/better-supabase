import type { BlockOf } from "../define-block.ts";
import type { ModerationEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { moderationEvents } from "./events.ts";
import { createModeration } from "./moderation.ts";
import { moderationSqlOptions } from "./options.ts";
import { moderationBinding } from "./record-binding.ts";

/** The `moderation` block's manifest (ADR 0029). */
export const moderationBlock: BlockOf<
  "moderation",
  typeof createModeration,
  ModerationEvents,
  Record<never, never>,
  never,
  typeof moderationBinding
> = defineBlock({
  name: "moderation",
  sql: ["moderation"],
  options: { moderation: moderationSqlOptions },
  events: moderationEvents,
  create: createModeration,
  record: moderationBinding,
  category: "collaboration",
  entities: { moderation_item: { mutability: "state-machine" } },
  concerns: ["lifecycle"],
  description:
    "Reports on any subject, a review queue, decisions (approve, hide, remove, restore, ban) with a log, user bans and an automatic hide threshold. Reviews moderate through it, and it hides and removes messages, comments included.",
});
