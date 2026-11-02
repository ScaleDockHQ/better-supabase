import type { BlockOf } from "../define-block.ts";
import type { TillsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { tillsEvents } from "./events.ts";
import { tillInputSchema } from "./schemas.ts";
import { createTills } from "./tills.ts";

/** The `tills` block's manifest (ADR 0029). */
export const tillsBlock: BlockOf<"tills", typeof createTills, TillsEvents> =
  defineBlock({
    name: "tills",
    sql: ["tills"],
    events: tillsEvents,
    schemas: { till: { input: tillInputSchema } },
    create: createTills,
    recipes: [],
    category: "commerce",
    description:
      "Till sessions with an opening float, cash in and out, end-of-day counts that book their difference in accounting, and cash deposits that reconcile to bank transactions.",
  });
