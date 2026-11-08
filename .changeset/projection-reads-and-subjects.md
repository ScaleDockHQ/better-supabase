---
"better-supabase": minor
---

Reads and cache tags follow the app's projection views. A generated block read (`reads.attachments.list`) also lists the typed key of each view your schema files project over a table it reads, so a block write invalidates a read served from the view. `hooks.ts` writes no hooks for a block table that a view projects, and doctor BS351 reports a write through such a view. `powersync streams` scopes an attachments view that keeps several subjects (`subject_type in ('job', 'quote')`) to the rows of each subject's own table, and the Lienlink fixture streams `job_parties` as a child of `jobs`.
