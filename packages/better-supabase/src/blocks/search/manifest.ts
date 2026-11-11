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
  options: { search: searchSqlOptions },
  provides: { sink: (client) => searchSink(client) },
  create: createSearch,
  client: "search",
  category: "work",
  description:
    "A search_documents index kept up by triggers from each config.recordTypes search entry, with search(q) as the caller (websearch, trigram prefixes, can_subject, hybrid with embeddings), and recents and favorites from the share-links user state.",
  recipes: ["command-search"],
});
