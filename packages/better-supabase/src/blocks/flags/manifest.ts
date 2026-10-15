import type { BlockOf } from "../define-block.ts";
import type { FlagsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createFlagAdmin } from "./admin.ts";
import { flagsEvents } from "./events.ts";

/** The `flags` block's manifest (ADR 0029). */
export const flagsBlock: BlockOf<"flags", typeof createFlagAdmin, FlagsEvents> =
  defineBlock({
    name: "flags",
    sql: ["flags"],
    events: flagsEvents,
    create: createFlagAdmin,
    category: "operations",
  });
