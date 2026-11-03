---
"better-supabase": minor
---

New `better-supabase/json-render` applies, collapses and validates json-render specs. `assistant({ parts: { compact } })` rewrites the response before it is saved, and the ai-files document kind `spec` stores a spec (`ai-files` SQL version 3, so run `better-supabase upgrade`).
