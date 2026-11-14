---
"better-supabase": minor
---

Workflow editor: three additions and a migration. An `event` trigger kind starts
a run for each block event whose type is `config.event` (or a `prefix.*`
pattern): `builder.triggers.fire(event)` does it, and
`subscribeEventTriggers(betterSupabase, builder)` calls it from
`betterSupabase.events.on("block", ...)` without ever changing the result of
the work that emitted the event. A node kind with `waits: true` pauses the run
after its step: `GraphRuntime.waitFor` registers the hook `nodeWaitToken(runKey,
node)`, and the node is called a second time with `call.resumed` once the hook
resumes (`compileGraph` emits the same calls); `nodeRunReporter` takes `{ waits:
true }` to record `waiting`. Node run records keep the step's input
(`WorkflowNodeRun.input`, `NodeRunRecord.input`), recorded with `running`.

Run `better-supabase upgrade` and apply the migration it generates: it adds
`workflow_node_runs.input`, replaces `record_workflow_node_run` with a version
that takes `input` last, adds `workflow_event_targets`, and adds `event` to the
trigger kind check. An app whose own enum types the trigger kind adds the value
`event` to it.
