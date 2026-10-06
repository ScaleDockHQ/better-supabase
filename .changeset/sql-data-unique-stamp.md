---
"better-supabase": patch
---

`better-supabase sql data` stamps its migration after every file in the migrations folder whose name starts with a timestamp, also when no underscore follows it (`<stamp>-seeds.sql`, `<stamp>.sql`), so it never shares a timestamp with a migration another tool such as PermDock's `--seeds-out` wrote.
