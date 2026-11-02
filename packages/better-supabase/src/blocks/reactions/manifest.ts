import type { BlockOf } from "../define-block.ts";
import type { ReactionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { reactionsEvents } from "./events.ts";
import { reactionsSqlOptions } from "./options.ts";
import { createReactions } from "./reactions.ts";
import { reactionsBinding } from "./record-binding.ts";

/** The `reactions` block's manifest (ADR 0029). */
export const reactionsBlock: BlockOf<
  "reactions",
  typeof createReactions,
  ReactionsEvents,
  Record<never, never>,
  never,
  typeof reactionsBinding
> = defineBlock({
  name: "reactions",
  sql: ["reactions"],
  options: { reactions: reactionsSqlOptions },
  events: reactionsEvents,
  record: reactionsBinding,
  create: createReactions,
  client: "reactions",
  category: "collaboration",
  recipes: ["reactions-bar"],
});
