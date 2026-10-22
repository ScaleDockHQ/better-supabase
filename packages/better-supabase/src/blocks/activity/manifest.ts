import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createActivity } from "./activity.ts";

/** The `activity` block's manifest (ADR 0029, ADR 0063). */
export const activityBlock: BlockOf<"activity", typeof createActivity> =
  defineBlock({
    name: "activity",
    sql: ["activity"],
    create: createActivity,
    category: "collaboration",
    recipes: [],
  });
