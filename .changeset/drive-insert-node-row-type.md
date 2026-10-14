---
"better-supabase": patch
---

The drive module drops `drive_insert_node` before it recreates it, so moving drive from a managed table to an adopted one (or renaming the table) no longer fails with "cannot change return type of existing function".
