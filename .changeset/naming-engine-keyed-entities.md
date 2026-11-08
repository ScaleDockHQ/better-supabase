---
"better-supabase": minor
---

The tasks block's default entity noun is `task`, not `work_item`: its functions take a `task` argument, its events carry `taskId` and its subject paths start with `tasks/`. An app that names the entity `work_item` in `blocks.tasks.names` keeps its tables and functions; its event types follow the entity (`work_item.created`). The built-in goal metric is `tasks.completed`, so run `upgrade` and apply the migration that updates stored goals. `TABLE_RENAMES` and `spec.formerly` are gone: permission keys such as `tasks.read` keep their names when you rename the entity.

| Old                    | New               |
| ---------------------- | ----------------- |
| `work_item` (default)  | `task`            |
| `workItemId` (default) | `taskId`          |
| `bsb_work_item_guard`  | `bsb_task_guard`  |
| `work_items.completed` | `tasks.completed` |
