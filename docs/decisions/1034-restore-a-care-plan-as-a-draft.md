# 1034: Restore a care plan as a draft (lane Y2, slice 2)

- Status: accepted
- Date: 2026-11-15
- Amends: 1028

## Context

ADR 0839 pairs every `archive` with a `restore`. The care plan was the one
block left without it, because its archive does more than hide a row: it ends
the plan's open actions with the reason `plan archived`, and `publish` also
archives the plan that was active and ends its actions as `superseded`. A
restore had to say what comes back and whether an ended action does.

## Decision

`restore(planId)` turns an archived plan into a `draft`, clears `archivedAt`
and records `care_plan.restored`. It needs `care_plans.publish`, like `archive`.

- The plan is never restored as `active`. A client has at most one active plan
  (a unique index), and a plan that was replaced must not displace the plan in
  force; the caller publishes the draft when it should apply.
- The actions stay ended. An ended action holds the dates it ran and a reason,
  and a care record must not claim that care ran during the gap. `publish`
  starts only `planned` actions, so a restored plan starts nothing until the
  caller adds actions, which is why the plan comes back with no running actions.
- `publishedAt`, the version snapshot and the agreement stay as they were, so
  the history of the plan is intact. Publishing the draft again records a new
  snapshot.
- Restoring a plan that is not archived returns it unchanged and records
  nothing, as the other restores do.

## Consequences

The block gains one security-definer function and one event. No column
changes. A caller that wants the old actions again copies the plan with
`copyFromPlanId`, which creates a draft with the problems, goals and actions of that plan.
