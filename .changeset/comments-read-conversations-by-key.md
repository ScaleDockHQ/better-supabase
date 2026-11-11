---
"better-supabase": patch
---

`list_comments`, `get_comment` and the other comment reads look up the record's conversation and work items by key, and `message_authors` checks only the conversations of the messages it was given, so a comment read no longer checks every conversation the caller can read. Reading one comment as a member of 50 tenants with 150 record conversations asks `can_subject` 5 times instead of 154. Run `better-supabase upgrade` and generate a migration.
