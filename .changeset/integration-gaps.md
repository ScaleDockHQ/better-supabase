---
"better-supabase": minor
---

Installed blocks now work together where they overlap. `ai-chat` records each
run's tokens on the `ai.input_tokens` and `ai.output_tokens` meters when
`usage` is installed (turn it off with `meterUsage: false`). `knowledge`
queues ingestion through `queue` (`ingest.queue` and `ingestJob()`). With
`invoices` installed, a paid order creates, issues and pays an invoice and
returns its id. Quote lines that name a catalog variant take its price and
title when they leave them out. Time entries and leave requests carry an
`employee_id` when `employees` is installed. `attachments` takes a
`publicBuckets` option and `Attachments.publicUrl()` for files anyone may
read. The registry adds `@better-supabase/ai-chat-next`, the AI chat route
with its stream and stop routes.
