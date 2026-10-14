---
"better-supabase": minor
---

`startOnEvent` and the schedule starts of `workflowStarter` take `runAs`: a publisher and the permission keys the run may use, or a function of the event or start call that returns them. The run starts as the publisher, capped to those keys, and the event's actor or the schedule's creator is recorded as `bs.trigger` for audit only. `WorkflowStartCall` gains `source`, and `WORKFLOW_PUBLISHER_FORBIDDEN` errors carry the missing keys as `permissions`, in the `DbError` and in Problem Details.

Breaking: a schedule start without `runAs` throws, so a schedule no longer runs with the rights of the member who created it.
