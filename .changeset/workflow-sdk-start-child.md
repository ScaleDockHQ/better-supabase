---
"better-supabase": minor
---

`better-supabase/workflow-sdk` adds `startChild`, which starts a child run with the parent's tenant, actor, ticket and subject. `approvalWaiter.wake` retries a missing hook up to four times, so an approval decided before the run reaches `createHook` still resumes it. `createWorkflows` returns `Workflows<F>`, with the extra run columns from `fields` typed and parsed on `run.fields`. `teeToStore` counts UTF-8 bytes for `flushBytes`.
