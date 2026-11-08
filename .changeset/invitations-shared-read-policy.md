---
"better-supabase": minor
---

When tenant and platform invitations share one table, the table now gets one select policy that reads both. The declarative output dropped the platform clause, so platform invitations stayed unreadable.
