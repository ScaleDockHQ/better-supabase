---
"better-supabase": minor
---

`createDataLifecycle` has `startExportJob(options)`, which returns `{ jobId: "export:<id>" }`, and `jobs`, the `export` source of `createJobs`. `createWorkflows` has `jobs`, the `workflow` source, which reads a run as the common job result. Both read through the caller's own permissions and fail with `DATA_EXPORT_FAILED`, `WORKFLOW_RUN_FAILED` or `WORKFLOW_RUN_CANCELLED`. Nothing existing changes.
