import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { streamsSqlOptions } from "./options.ts";

/** The `streams` block's manifest (ADR 0029). */
export const streamsBlock: Block<"streams"> = defineBlock({
  name: "streams",
  sql: ["streams"],
  options: {
    streams: streamsSqlOptions,
  },
  category: "platform",
});
