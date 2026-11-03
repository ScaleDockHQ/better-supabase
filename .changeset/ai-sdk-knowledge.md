---
"better-supabase": minor
---

The `Embedder` interface accepts `apiVersion: 2`, whose `embed` returns `{ embeddings, usage?: { tokens } }`; version 1 embedders keep working, and `embedVectors` normalizes both. `embedWith` from `better-supabase/ai-sdk/embeddings` now returns a version 2 embedder that reports the AI SDK 7 `embedMany` `usage.tokens`, so code that called `embedWith(...).embed(values)` directly reads `.embeddings`. `KnowledgeHit` gains `chunkId` and `organizationId`, `createKnowledge` takes `dimensions` (the hint `KNOWLEDGE_DIMENSION_MISMATCH`) and `priorityOrder`, and the memory block accepts the same embedders. The knowledge module is now version 6: `knowledge_search` takes `priority_order` (default true, false ranks by score alone) and returns `chunk_id` and `organization_id`, so run the upgrade migration to replace the function; the earlier signature is dropped.
