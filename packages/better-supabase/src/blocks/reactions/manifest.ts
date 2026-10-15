import type { BlockOf } from "../define-block.ts";
import type { ReactionsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { reactionsEvents } from "./events.ts";
import { reactionsSqlOptions } from "./options.ts";
import { createReactions } from "./reactions.ts";

/** The `reactions` block's manifest (ADR 0029). */
export const reactionsBlock: BlockOf<
  "reactions",
  typeof createReactions,
  ReactionsEvents
> = defineBlock({
  name: "reactions",
  sql: ["reactions"],
  options: {
    reactions: reactionsSqlOptions,
  },
  events: reactionsEvents,
  create: createReactions,
  client: "reactions",
  category: "collaboration",
});
