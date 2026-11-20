---
"better-supabase": patch
---

Keep one `ai` draft per conversation and `replyKey` in the inbox, in any status. `suggest_inbox_draft` returns the existing draft when its metadata `replyKey` matches, so a replayed eve session sync pass no longer adds a draft after staff sent or discarded the first. Inbox module version 11 adds the unique index `inbox_drafts_ai_key`; run `better-supabase upgrade` to apply it.
