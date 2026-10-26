---
"better-supabase": patch
---

`employee_from_application` works over a hiring jobs table of your own: it compares an enum employment type by its text, maps it back through `blocks.hiring.values`, and leaves the team or employment type empty when the jobs table has no column for it instead of failing to render.
