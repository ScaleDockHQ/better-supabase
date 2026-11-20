---
"better-supabase": minor
---

Add the Phase 5 blocks for eve on Supabase.

- `ai-chat`: a `modes` option that adds a check constraint on `mode` and narrows the `mode` type of chats, inputs and patches.
- `better-supabase/blocks/memory`: `importMemories` copies a table into archival memory and keeps its embeddings, and `archival.upsert` takes `embedding` and `embeddingModel`.
- `better-supabase/eve`: `supabaseMemory({ scopes })` recalls and writes the user, organization and record scopes, with read-only shared scopes unless `write: true`.
- `better-supabase/blocks/knowledge`: `position` (offsets, page, heading) on chunks and hits, `pdfExtractor`, `docxExtractor` and `extractors` that take the library through `load`, and `createUrlSource` with `resync`, `resyncAll` and fetch guards.
- `better-supabase/eve`: `validateExpression`, `queueScheduleProvider({ scopes, minIntervalMs, validateExpression })`, `queueDynamicSchedules({ notify, staleAfterMs })` and `aiScheduleDispatch`, which runs `ai-schedules` tasks as eve sessions.

No new dependency is pinned. The PDF and DOCX libraries stay with the app.
