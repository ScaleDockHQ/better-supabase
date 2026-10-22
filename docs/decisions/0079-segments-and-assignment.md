# 0079: Materialize segments from rules filter trees and route records through assignment queues

- Status: accepted
- Date: 2026-10-22

## Context

A CRM groups records into lists that update themselves ("SaaS customers",
"deals over 50k without a next step") and starts work when a record joins
one. It also routes new leads to reps by turn, by weight or by territory.
The rules block already defines a filter tree, a per subject type field
catalog and an evaluator that gives the same answer in TypeScript and SQL
(ADR 0046). Sequences and lead scoring sit on enrollments and scores, which
another stack adds, so this stack doesn't build them.

## Decision

Add a `segments` block (`src/sql/modules/segments.ts`,
`src/blocks/segments/`). A segment stores one filter tree over one
registered subject type, checked against `rule_field_map` when it is saved.
`evaluate_segment` renders one static branch per `config.subjects` entry
that runs `rule_matches` on `to_jsonb(row)`, skips rows with the subject's
`deletedAt`, and diffs the matches against `segment_members`: it inserts
the new ones, deletes the gone ones and writes `segment.entered` and
`segment.left` per record. Membership is materialized, refreshed by
`refresh_segment` or by `refresh_due_segments` on a schedule, and capped by
the `maxMembers` option (10,000). Because refresh reads the stored row,
rule fields used in segments name database columns.

Add an `assignment` block (`src/sql/modules/assignment.ts`,
`src/blocks/assignment/`). A queue covers one subject type, a strategy
(`round_robin` or `weighted`) and an optional territory filter tree.
`assign_subject` locks the first enabled matching queue by rank and picks
the member who waited longest, or uses smooth weighted round robin over a
stored credit per member. It logs the pick in `assignments` and writes
`subject.assigned`; it doesn't write the owner column, so one block serves
companies, deals and tickets. Both blocks add tenant-scoped permissions
(`segments.read`/`edit`, `assignment.read`/`manage`/`assign`) to the access
model.

## Alternatives considered

- Segments as live views or a query at read time. A view can't tell who
  entered or left, so it gives no events, and counting a large segment on
  every page view costs more than a scheduled refresh.
- Refresh on every write through triggers on each subject table. It turns
  every insert into an evaluation of every segment of that type, and the
  subject tables belong to other blocks and the app.
- Writing the owner in `assign_subject`. Owner columns differ per subject
  (`owner_user_id`, `assignee_id`, an app column), and an event lets the
  app set it, notify the owner and start a task in one place.
- Random weighted picks. They drift over short runs; smooth weighted round
  robin keeps every window of picks close to the weights.

## Consequences

Any subject with synced rule fields can be segmented or routed with no new
SQL per type. Large segments need a cap and a schedule rather than
real-time updates, and a subject without `deletedAt` (parties and deals
archive with `archived_at`) needs an explicit "is empty" condition to leave
archived records out. Sequences can enroll on `segment.entered`, and lead
scoring can feed a score into segment conditions once the enrollments and
scores blocks land. There is no UI recipe yet, and both blocks are only in
the `everything` preset.
