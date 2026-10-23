import type { BlockOf } from "../define-block.ts";
import type { ScoresEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { scoresEvents } from "./events.ts";
import { scoresSqlOptions } from "./options.ts";
import { scoresBinding } from "./record-binding.ts";
import { createScores } from "./scores.ts";

/** The `scores` block's manifest (ADR 0029). */
export const scoresBlock: BlockOf<
  "scores",
  typeof createScores,
  ScoresEvents,
  Record<never, never>,
  never,
  typeof scoresBinding
> = defineBlock({
  name: "scores",
  sql: ["scores"],
  options: { scores: scoresSqlOptions },
  events: scoresEvents,
  create: createScores,
  record: scoresBinding,
  category: "growth",
});
