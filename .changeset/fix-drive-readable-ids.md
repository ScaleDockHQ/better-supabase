---
"better-supabase": patch
---

Fix the drive set readers (`drive_readable_ids` and `drive_drive_readable_ids`) with provider row grants. They now ask the provider's `rowsWith` function once per mapped role, with the candidate ids as one `text[]`, instead of once per node. Run `bsb sql upgrade` to apply the new function bodies.
