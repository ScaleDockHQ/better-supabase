---
'better-supabase': patch
---

Saved snapshots keep `functions` and `roleSettings` when doctor reads them, so the RLS checks
(BS205 to BS207, BS210, BS211) see the same data as a live run.
