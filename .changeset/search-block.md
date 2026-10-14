---
"better-supabase": minor
---

Adds the `search` block (`better-supabase/blocks/search`). Triggers generated from each `search` entry in `config.subjects` keep a `search_documents` index, and `search(q)` runs as the caller with websearch, prefix and trigram matching, filtered by `can_subject`, and ranked hybrid when the index keeps embeddings. Recents and favorites come from the share-links user state, trashed rows drop out, `searchSink` handles trash events, and `useCommandSearch` (`better-supabase/blocks/search/react`) drives a Cmd+K dialog.
