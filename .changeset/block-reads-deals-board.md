---
"better-supabase": minor
---

Blocks can ship composed reads. `deals.board({ pipelineId })` returns a pipeline's stages with their deals, counts, totals per currency and the weighted forecast in one call, from the new `deal_board` function. `better-supabase gen` writes `reads` and a result type for each read into `blocks.generated.ts`, `defineReadSet` takes them as `blocks: reads`, and the block catalog lists them.
