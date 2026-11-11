---
"better-supabase": patch
---

`list_comments`, `comment_counts` and `messaging_messages_json` check each conversation once and read its messages by key, so a read no longer weighs every conversation the caller can see across tenants. What each caller sees stays the same. `list_comments_unchecked` and `messaging_messages_json_unchecked` return the same rows without a check, for an app's own `security definer` function after its own check; they are granted to `service_role` only.
