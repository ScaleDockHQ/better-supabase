---
"better-supabase": patch
---

Fix `finish_import` in the `imports` SQL module: its `id` parameter clashed with the runs table's `id` column, so finishing a run raised "column reference is ambiguous".
