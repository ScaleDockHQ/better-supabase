---
"better-supabase": minor
---

Postmortem `actionItems` and the `action_items` column are removed from the `incidents` block. Write
action items with `addPostmortemAction` (the `tasks` block) and read a postmortem's `actions`. Run
`better-supabase upgrade` before you diff: its new step copies the items of an existing database into
tasks and then drops the column, and it stops with an error instead of dropping items it can't copy.
`codemod 0.47` lists the lines that use `actionItems`.
