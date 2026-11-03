---
"better-supabase": minor
---

`appTables.<name>.embedding` (or the `@bsb embedding` tag) keeps a vector column current from the table's text columns through pgmq, pg_net and pg_cron. Serve the worker with `embeddingWorker` or `drainEmbeddings` from `better-supabase/ai-sdk/embeddings`; `renderAutoEmbedding` in `better-supabase/sql` renders the same SQL for other tables. `blocks.knowledge.options.autoEmbed` (knowledge module version 7) sends pending chunks to the same worker. Doctor gains BS241 (embedding jobs read five times or more) and BS242 (failed pg_net requests).
