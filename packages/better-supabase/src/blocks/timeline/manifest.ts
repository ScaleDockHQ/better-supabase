import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createTimeline } from "./timeline.ts";

/** The `timeline` block's manifest (ADR 0029, ADR 0063). */
export const timelineBlock: BlockOf<"timeline", typeof createTimeline> =
  defineBlock({
    name: "timeline",
    sql: ["timeline"],
    create: createTimeline,
    category: "collaboration",
    recipes: [],
  });
