---
"better-supabase": minor
---

Add the Phase 5 blocks for eve on Supabase.

- `ai-chat`: a `modes` option that adds a check constraint on `mode` and narrows the `mode` type of chats, inputs and patches.
- `better-supabase/blocks/memory`: `importMemories` copies a table into archival memory and keeps its embeddings, and `archival.upsert` takes `embedding` and `embeddingModel`.
- `better-supabase/eve`: `supabaseMemory({ scopes })` recalls and writes the user, organization and record scopes, with read-only shared scopes unless `write: true`.
- `better-supabase/blocks/knowledge`: `position` (offsets, page, heading) on chunks and hits, `pdfExtractor`, `docxExtractor` and `extractors`, which load the optional peers `unpdf` and `mammoth` on first use (or take a library through `load`), and `createUrlSource` with `resync`, `resyncAll` and fetch guards.
- `better-supabase/eve`: `validateExpression`, `queueScheduleProvider({ scopes, minIntervalMs, validateExpression })`, `queueDynamicSchedules({ notify, staleAfterMs })` and `aiScheduleDispatch`, which runs `ai-schedules` tasks as eve sessions.

- `ai-schedules`: tasks have a `source` and an `externalId`, and the new service functions `mirror`, `unmirror` and `recordRun` let another scheduler keep tasks and runs in `ai_scheduled_tasks` and `ai_task_runs`. The dispatcher only claims tasks whose source is `ai-schedules`. The module is version 3; run `better-supabase upgrade`.
- `better-supabase/eve`: `queueScheduleProvider({ mirror })` writes eve's dynamic schedules and their occurrences to those tables.

`unpdf` and `mammoth` are new optional peers (`>=2.2.1 <3` and `>=1.13.0 <2`).
