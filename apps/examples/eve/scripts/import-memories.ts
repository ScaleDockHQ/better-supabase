import { importMemories } from "better-supabase/blocks/memory";
import { createPostgres } from "better-supabase/postgres";

import { memory } from "../agent/lib/blocks.ts";

// One-off: copies a legacy `agent_memories` table into the memory block and
// keeps its embeddings, so the history needs no new embedding calls.
// Run `pnpm import:memories <organization-id>` with a DATABASE_URL.
const organizationId = process.argv[2];

if (organizationId === undefined) {
  throw new Error("Usage: pnpm import:memories <organization-id>");
}

const source = createPostgres();

const result = await importMemories({
  memory,
  source: source.admin,
  table: "legacy.agent_memories",
  organizationId,
  columns: { category: "kind" },
  embeddingModel: "text-embedding-3-small",
}).orThrow();

console.log(`Imported ${result.imported}, skipped ${result.skipped}.`);
