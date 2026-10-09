---
"better-supabase": minor
---

The `knowledge` and `memory` SQL modules give agents retrieval and long-term memory; both require `vector-search`.

- `createKnowledge` in `better-supabase/blocks/knowledge` stores documents scoped to an organization, agent, project, chat or user, chunks them with embeddings and a `tsvector`, and searches with reciprocal rank fusion. With `jobs` installed new documents are enqueued for embedding; `ingest.file` reads an `ai-files` upload.
- `createMemory` in `better-supabase/blocks/memory` keeps core memory files under `/memories`, archival facts and one embedding per chat message, plus versioned `memory.documents`.
- `better-supabase/ai-sdk/embeddings` adds `embedWith`, `supabaseEmbed`, `rerankWith`, `searchTool` and `toSourceParts`, and `/ai-sdk/memory` adds `memoryTool`, `anthropicMemory`, `recallTool`, `withMemory` and the `extractMemories` job handler.
- An item rewritten while it is being embedded stays pending, `set_memory_embeddings` writes a batch, bad vectors fail with `EMBEDDING_INVALID`, and knowledge `drain` tries each document `attempts` times (3) before marking it failed.
