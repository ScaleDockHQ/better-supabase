---
"better-supabase": patch
---

A platform invitation stores its role in the role column's own type instead of casting it to `text`, so an adopted invitations table shared with tenant invitations whose role column is a uuid through a roles table (`platformRoles.through`) accepts platform invitations. They also write `prefill` when the shared table has that column, and return it from `invite_member`, `invitation_preview` and `my_invitations`.
