# 0077: Enrollments in programs of steps, with onboarding on top

- Status: accepted
- Date: 2026-10-22

## Context

Apps track people and records through ordered steps: customer onboarding
plans, training paths, implementation checklists. The `onboarding` block
did this for one case only, getting-started checklists, in its own
`onboarding_progress` table keyed by checklist and step. A second block for
customer programs would have copied the same rows, permissions and events,
and an admin page could not list both.

## Decision

An `enrollments` block keeps programs per organization (`key`, ordered
`steps` as `{ id, title, description }`, allowed subject types, a `version`
raised when the steps change) and enrollments of a subject, any
`(subject type, subject id)`, in a program. An enrollment snapshots the
program's step ids, counts its completed steps against that snapshot, and is
`active`, `completed` or `cancelled`. Completed steps are rows in
`enrollment_steps` with who completed them. The tenant column is nullable so
a user's own checklist, which belongs to no organization, fits the same
tables; a `user` subject carries `user_id`, so the user reads and completes
their own enrollment and the row goes with the user.

Two internal functions, `enrollment_ensure` and `enrollment_mark`, create an
enrollment and mark a step without a permission check, so a block that drives
its own programs keeps its own permissions. Onboarding is that block: it goes
to version 2, requires enrollments, and runs each checklist as the program
`onboarding:<checklist>` with the steps from `defineChecklist`. Its functions
and client keep their signatures and results. Its upgrade creates an
enrollment per checklist and subject, copies the completed steps, and drops
`onboarding_progress`. Program keys an organization saves can't hold a colon,
so module programs never clash with them and can't be cancelled.

## Consequences

- One set of tables, events (`enrollment.*`) and permissions
  (`enrollments.read`, `enroll`, `manage`) covers onboarding and app programs.
- Onboarding keeps `onboarding.read` and `onboarding.complete`; the generic
  functions also let `enrollments.enroll` complete an organization checklist.
- Only enrollments in an organization emit events, so user checklists stay
  quiet as before.
- Sequences and courses (timed steps, content per step) are a follow-up on
  these tables; this block has no scheduling.
- Inserting the module before onboarding shifts the later module file numbers
  by one; the 0.13 to 0.14 guide says to resync.
