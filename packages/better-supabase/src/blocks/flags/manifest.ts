import type { BlockOf } from "../define-block.ts";
import type { FlagsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createFlags } from "./admin.ts";
import { flagsEvents } from "./events.ts";
import { flagsSqlOptions } from "./options.ts";

/** The `flags` block's manifest (ADR 0029). */
export const flagsBlock: BlockOf<"flags", typeof createFlags, FlagsEvents> =
  defineBlock({
    name: "flags",
    sql: ["flags"],
    options: {
      flags: flagsSqlOptions,
    },
    events: flagsEvents,
    create: createFlags,
    category: "growth",
  });
