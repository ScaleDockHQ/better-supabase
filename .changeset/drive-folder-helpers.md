---
"better-supabase": minor
---

New drive helpers: `drive.folder`, `drive.can`, `drive.search`, `drive.put`, `drive.shareMany` and `drive.grantsWithNames`. They use the new SQL functions `drive_node_access` and `drive_search`. Run `better-supabase upgrade` and apply the migration to get them.
