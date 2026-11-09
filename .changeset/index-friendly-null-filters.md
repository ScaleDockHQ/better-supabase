---
"better-supabase": minor
---

`knowledge_search` sets `plan_cache_mode = force_custom_plan`, so the planner folds a null `collections` argument and uses the collection index. `mark_notifications_read` reads its `ids` argument through a union of the given ids and the user's unread rows instead of `ids is null or id = any(ids)`, and `list_notifications` and `notification_page` filter `types` with `type = any(coalesce(types, array[type]))`. `better-supabase upgrade` rewrites the knowledge and notifications modules; add the generated `create or replace function` migration. No data moves.
