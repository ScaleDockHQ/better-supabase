---
"better-supabase": patch
---

The generated permission list now has every optional key a block checks when you set it:
`purge` for teams, employees, time entries, activities, agents, announcements, care rules,
courses, field definitions, enrollment programs, forms, funding claims, maintenance plans,
meetings, posts and score models, the finer quote keys (`send`, `accept`, `reject`,
`requestChanges`, `withdraw`) and `impersonation.approve`. Teams no longer list `delete`, which
became `purge` in 0.67.
