---
"better-supabase": minor
---

The `knowledge` SQL module and `createKnowledge` in `better-supabase/blocks/knowledge` store documents for retrieval, scoped to an organization, agent, project, chat or user. Text is split into chunks that each carry an embedding and a `tsvector`, a chunk keeps its embedding when its text and model are unchanged, and search fuses full text and vector rankings with reciprocal rank fusion. With `jobs` installed a new document is enqueued for embedding; without it, `process` and `drain` embed on the server. `ingest.file` reads an `ai-files` upload.

The `memory` SQL module and `createMemory` in `better-supabase/blocks/memory` keep core memory files under `/memories` that `run` edits with the commands of Anthropic's memory tool, archival facts found by similarity, and one embedding per chat message for recall across chats.

`better-supabase/ai-sdk/embeddings` adds `embedWith`, `supabaseEmbed`, `rerankWith`, the `searchTool` for the model and `toSourceParts`. `better-supabase/ai-sdk/memory` adds `memoryTool`, `anthropicMemory` for `memory_20250818`, `recallTool`, `withMemory` and the `extractMemories` job handler. Both modules require `vector-search`.
