---
"better-supabase": minor
---

The `Embedder` interface accepts `apiVersion: 2`, whose `embed` returns `{ embeddings, usage?: { tokens } }`; version 1 embedders keep working, and `embedVectors` normalizes both. `embedWith` from `better-supabase/ai-sdk/embeddings` now returns a version 2 embedder that reports the AI SDK 7 `embedMany` `usage.tokens`, so code that called `embedWith(...).embed(values)` directly reads `.embeddings`. `KnowledgeHit` gains `chunkId` and `organizationId`, `createKnowledge` takes `dimensions` (the hint `KNOWLEDGE_DIMENSION_MISMATCH`) and `priorityOrder`, and the memory block accepts the same embedders. `priorityOrder: false` reorders on the client only. The SQL `knowledge_search` columns `chunk_id`, `organization_id` and `priority_order` are not part of this change, and `pnpm catalog` still has to regenerate the hint codes.
