---
"better-supabase": patch
---

Deal contacts, subject knowledge and deadlines read through inline subject policies, so a read of 12,000 rows on 60,000 customers takes tens of milliseconds instead of seconds. The retention, hold, approval and audit memos keep their keys in 256 settings per connection instead of one per statement, a reply adds to its thread root in place instead of recounting the thread, `messages` gains an index on `conversation_id` alone, and fifteen `(tenant_id, created_at desc)` indexes end in `id desc`. Run `better-supabase upgrade` and generate a migration.
