---
"better-supabase": minor
---

Doctor adds BS375 (two policies that decide the same way) and BS376 and BS377 (objects a migration creates and no schema file declares, and the reverse, under pg-delta) and BS378 (the `extraColumns` options). `upgrade --check` also fails on `transaction=false`, a top-level `insert`, an object two block files declare and duplicate policies; its result data reports them as `problems`, not `duplicated`.
