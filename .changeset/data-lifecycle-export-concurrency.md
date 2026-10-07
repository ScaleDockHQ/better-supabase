---
"better-supabase": minor
---

`createDataExporter({ concurrency })` exports that many tables at a time (4 by default) instead of one after another, so an organization with hundreds of tenant tables exports in a fraction of the time. Files keep the table order, the first failing table stops new ones from starting, and `concurrency: 1` keeps the previous sequential behaviour.
