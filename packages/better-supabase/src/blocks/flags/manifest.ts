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
    options: { flags: flagsSqlOptions },
    events: flagsEvents,
    create: createFlags,
    category: "growth",
    entities: {
      flag: {
        mutability: "editable",
        emits: { create: true, update: true, delete: true },
      },
    },
    description:
      "Feature flags with variants, targeting rules over tenant, user, plan, role, custom contexts such as brand and shared segments, overrides, and a scheduled percentage rollout split across weighted variants, bucketed by SHA-256. Every save records a revision you can restore. flag_enabled() goes in policies; createFlagsProvider() evaluates the same way for OpenFeature and the Flags SDK.",
    recipes: ["feature-flag-toggles"],
  });
