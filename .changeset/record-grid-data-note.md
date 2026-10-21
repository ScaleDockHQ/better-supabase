---
"better-supabase": patch
---

The Record grid recipe, on the UI recipes page and in the skill reference, now notes that a copy of `@reui/data-grid` installed from ReUI 2.8.0 or earlier doesn't repaint after an edit that keeps the row count. Reinstall it with `npx shadcn add @reui/data-grid --overwrite`, or add `table.options.data` to the dependency list of the `value` memo in `DataGridProvider`.
