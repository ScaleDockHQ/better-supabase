---
"better-supabase": minor
---

`revoke_ai_chat_share` no longer fails `supabase db lint` with an ambiguous `id` column: the lookup in `share_links` qualifies its columns. Run `better-supabase upgrade` to rewrite the function.
