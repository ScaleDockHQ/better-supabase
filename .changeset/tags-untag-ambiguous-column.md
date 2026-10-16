---
"better-supabase": minor
---

The tags module's `untag` qualifies its columns, so its delete no longer fails with "column reference `tag_id` is ambiguous" against the function's own `tag_id` parameter, on the polymorphic `taggings` table and on adopted link tables.
