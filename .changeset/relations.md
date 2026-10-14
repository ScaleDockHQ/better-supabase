---
"better-supabase": minor
---

Add the `relations` block (`better-supabase/blocks/relations`). It links two subjects with a declared kind (`blocks`, `parent` and `relates` by default), stores inverse names from one end, refuses cycles for acyclic kinds under an advisory lock, replaces the target of one-target kinds, and reads ancestors, descendants and rollups. `link` and `unlink` return an undo token, and `toGanttTasks` and `toTreeItems` shape links for a Gantt chart or a tree.
