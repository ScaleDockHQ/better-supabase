---
"better-supabase": major
---

AI chat sharing moves onto the `share-links` block. `share_ai_chat`, `revoke_ai_chat_share`, `list_ai_chat_shares` and `get_shared_ai_chat` stay callable and use `share_links`. Existing `ai_chat_shares` rows are copied, including the leaf. New links are stored only as a hash.
