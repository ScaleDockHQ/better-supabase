import type { BlockOf } from "../define-block.ts";
import type { SharedSignalsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { sharedSignalsEvents } from "./events.ts";
import { sharedSignalsSqlOptions } from "./options.ts";
import { createSharedSignals } from "./shared-signals.ts";

/** The `shared-signals` block's manifest (ADR 0029). */
export const sharedSignalsBlock: BlockOf<
  "shared-signals",
  typeof createSharedSignals,
  SharedSignalsEvents
> = defineBlock({
  name: "shared-signals",
  sql: ["shared-signals"],
  options: {
    "shared-signals": sharedSignalsSqlOptions,
  },
  events: sharedSignalsEvents,
  create: createSharedSignals,
  category: "platform",
});
