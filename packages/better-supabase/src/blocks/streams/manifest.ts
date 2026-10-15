import type { Block } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";

/** The `streams` block's manifest (ADR 0029). */
export const streamsBlock: Block<"streams"> = defineBlock({
  name: "streams",
  sql: ["streams"],
  options: {
    streams: optionKeys(["topic"]),
  },
  category: "platform",
});
