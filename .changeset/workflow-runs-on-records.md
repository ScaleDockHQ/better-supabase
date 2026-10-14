---
"better-supabase": minor
---

Workflow runs can belong to a record. `workflow_runs` gains `subject_type`, `subject_id`, `principal_kind`, `principal_id`, `mode` (`live` or `test`) and `trigger_node`. `runs.list({ subject, mode })` filters by them, `admission.request({ subject })` queues a start for a record, outbox events carry `subjectType` and `subjectId`, and `startFor(ctx, workflow, args, { subject })` stores the record as the `bs.subject` attribute (`subjectAttribute` builds it). Test runs emit no outbox events and are left out of run lists by default.

Breaking: `record_workflow_run`, `workflow_runs_list` and `request_workflow_start` take the new arguments, and `sql sync` drops the old signatures. Runs that `startOnEvent` and `workflowStarter` start with `runAs` now record the user who triggered them as `bs.actor` (and `actor_id`), not the publisher; the publisher is in `principal_kind` and `principal_id`, and `runAs` takes `principalKind`. `startFor` drops `bs.principal_kind` and `bs.principal` from caller attributes. Run `better-supabase sql sync` to install version 2 of the `workflows` and `workflow-sdk-world` modules.
