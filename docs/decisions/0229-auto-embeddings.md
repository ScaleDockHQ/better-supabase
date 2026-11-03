# 0229: Embed app table rows through pgmq, pg_net and pg_cron

- Status: accepted
- Date: 2026-11-03

## Context

Apps that add a vector column keep embeddings current by hand.

## Decision

- `renderAutoEmbedding` renders the column, HNSW index, clear and enqueue triggers, a drain function and a cron job (guarded for a missing pg_cron). The worker URL and token come from Vault, and the vector type is qualified with the pgvector schema.
- `appTables.<name>.embedding` (`content`, `dimensions`, `type`, `schedule`, `batch`) and the `@bsb embedding` tag render it through `renderAutoEmbedding`. The content columns are own plain text columns, and the table can't have a column named `embedding`.
- `embeddingWorker` and `drainEmbeddings` embed a batch and call `<table>_apply_embedding`, which stores a vector only while the content hash matches.
- `blocks.knowledge.options.autoEmbed` adds a drain that posts the pending chunks of waiting documents as jobs (`<document id>:<chunk index>`, no queue message). Knowledge keeps its own keep-when-unchanged logic, so it doesn't use the clearing trigger.
- Doctor reports queue messages read five times or more (BS241) and failed `net._http_response` rows of the last hour (BS242).

## Consequences

Tables get embeddings from config alone. A knowledge drain can send a batch twice while the worker is busy; `set_knowledge_embeddings` checks each chunk's hash, so the second apply is harmless.
