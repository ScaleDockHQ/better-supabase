import type { BlockOf } from "../define-block.ts";
import type { DamEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createDam } from "./dam.ts";
import { damEvents } from "./events.ts";
import { damUsageRightInputSchema } from "./schemas.ts";

/** The `dam` block's manifest (ADR 0029). */
export const damBlock: BlockOf<"dam", typeof createDam, DamEvents> =
  defineBlock({
    name: "dam",
    sql: ["dam"],
    events: damEvents,
    schemas: { dam_usage_right: { input: damUsageRightInputSchema } },
    create: createDam,
    recipes: [],
    category: "content",
  });
