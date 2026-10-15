import type { BlockOf } from "../define-block.ts";
import type { HiringEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { hiringEvents } from "./events.ts";
import { createHiring } from "./hiring.ts";
import { hiringSqlOptions } from "./options.ts";

/** The `hiring` block's manifest (ADR 0029). */
export const hiringBlock: BlockOf<"hiring", typeof createHiring, HiringEvents> =
  defineBlock({
    name: "hiring",
    sql: ["hiring"],
    options: {
      hiring: hiringSqlOptions,
    },
    events: hiringEvents,
    create: createHiring,
    category: "work",
  });
