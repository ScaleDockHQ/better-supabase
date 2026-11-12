---
"better-supabase": minor
---

`notifications.page` sorts by `order` (`newest`, `oldest`, `type`, `subject` or `status`, with `_desc` forms) and filters on `excludeTypes`, `subjectIds` and `anyOf` groups, so a view such as "everything that is not an open request" pages in SQL. `search` in `list` and `page` also matches the actor's name when the `profiles` module is installed. Both return up to 500 items (was 200), and `page` returns the `limit` it applied, so a caller sees when a request was clamped. `notification_page` takes `exclude_types`, `subject_ids`, `any_of` and `order_by`; the notifications module goes to version 11.
