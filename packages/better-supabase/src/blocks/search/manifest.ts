import type { BlockOf } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createSearch } from "./search.ts";
import { searchSink } from "./sink.ts";

/** The `search` block's manifest (ADR 0029). */
export const searchBlock: BlockOf<"search", typeof createSearch> = defineBlock({
  name: "search",
  sql: ["search"],
  options: {
    search: optionKeys(["config", "dimensions"]),
  },
  provides: {
    sink: (client) => searchSink(client),
  },
  create: createSearch,
  client: "search",
  category: "work",
  recipes: ["command-search"],
});
