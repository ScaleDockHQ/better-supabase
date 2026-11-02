---
"better-supabase": patch
---

Index the foreign keys of the moderation DSA tables: `moderation_notices.item_id`, `moderation_flaggers.user_id` and `moderation_appeals.appellant_id`. Run `better-supabase upgrade` and add the generated migration.
