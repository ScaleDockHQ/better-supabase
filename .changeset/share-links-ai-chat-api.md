---
"better-supabase": patch
---

`sql sync` no longer stops with `blocks.share-links.api: found no definition of share_ai_chat(uuid, text) to wrap` when `share-links` and `ai-chat` are installed together with `sql.api` set. The four ai-chat sharing functions in the share-links module now put `returns` on its own line, so the Data API wrappers are written for them. Re-run `better-supabase sql sync` and generate a migration; the function bodies don't change.
