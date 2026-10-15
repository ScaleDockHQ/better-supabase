import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { searchSqlOptions } from "./options.ts";
import { createSearch } from "./search.ts";
import { searchSink } from "./sink.ts";

/** The `search` block's manifest (ADR 0029). */
export const searchBlock: BlockOf<
  "search",
  typeof createSearch,
  Record<never, never>,
  Record<never, never>,
  "sink"
> = defineBlock({
  name: "search",
  sql: ["search"],
  options: {
    search: searchSqlOptions,
  },
  provides: {
    sink: (client) => searchSink(client),
  },
  create: createSearch,
  client: "search",
  category: "work",
  recipes: ["command-search"],
});
