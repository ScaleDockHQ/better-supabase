import type { BlockOf } from "../define-block.ts";
import type { ModerationEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { moderationEvents } from "./events.ts";
import { createModeration } from "./moderation.ts";
import { moderationSqlOptions } from "./options.ts";
import { moderationSection } from "./section.ts";

/** The `moderation` block's manifest (ADR 0029). */
export const moderationBlock: BlockOf<
  "moderation",
  typeof createModeration,
  ModerationEvents,
  Record<never, never>,
  never,
  { readonly moderation: typeof moderationSection }
> = defineBlock({
  name: "moderation",
  sql: ["moderation"],
  options: { moderation: moderationSqlOptions },
  events: moderationEvents,
  create: createModeration,
  sections: { moderation: moderationSection },
  category: "collaboration",
});
