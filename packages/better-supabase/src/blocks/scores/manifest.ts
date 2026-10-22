import type { BlockOf } from "../define-block.ts";
import type { ScoresEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { scoresEvents } from "./events.ts";
import { scoresSqlOptions } from "./options.ts";
import { createScores } from "./scores.ts";
import { scoresSection } from "./section.ts";

/** The `scores` block's manifest (ADR 0029). */
export const scoresBlock: BlockOf<
  "scores",
  typeof createScores,
  ScoresEvents,
  Record<never, never>,
  never,
  { readonly scores: typeof scoresSection }
> = defineBlock({
  name: "scores",
  sql: ["scores"],
  options: { scores: scoresSqlOptions },
  events: scoresEvents,
  create: createScores,
  sections: { scores: scoresSection },
  category: "growth",
});
