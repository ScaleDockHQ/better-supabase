import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { vectorSearchSqlOptions } from "./options.ts";

/** The `vector-search` block's manifest (ADR 0029). */
export const vectorSearchBlock: Block<"vector-search"> = defineBlock({
  name: "vector-search",
  sql: ["vector-search"],
  options: { "vector-search": vectorSearchSqlOptions },
  category: "ai",
  entities: { vector_search: { mutability: "read-only" } },
  description:
    "search_<table>(query, k) for each table in vectorSearch: the k nearest rows the caller can read, with pgvector iterative index scans so RLS filters still return k rows.",
});
