# 0121: Enrollment steps carry an assignee and a due date, rendered into rows

- Status: accepted
- Date: 2026-10-28

## Context

ADR 0077 left scheduling out of `enrollments`: a program's steps had an id,
a title and a description, and `enrollment_steps` held one row per completed
step. Customer onboarding and implementation plans need more: the kickoff is
the account manager's job and is due two days after the start, the review is
due a week before the go-live date. Apps built this next to the block, with
their own task tables, and lost the link to the enrollment's progress.

## Decision

A program step can carry `assignee` (`{ role }` or `{ userId }`) and `due`
(`{ days, from }`, whole days from -3650 to 3650 after the enrollment's
`start` or `end`). Enrollments gain nullable `starts_at` and `ends_at`; the
start falls back to `enrolled_at`.

The schedule is rendered into rows, not computed on read. Each step with an
assignee or a due date gets a row in `enrollment_steps` with
`assignee_role`, `assignee_user_id` and `due_at`, and `completed_at` becomes
nullable: a row with no `completed_at` is an open step. An internal
`enrollment_schedule` function renders the rows when a subject enrolls, when
`set_enrollment_dates` changes the dates and when a step is reset; it keeps
completion and removes open rows for steps that lost their schedule.
Progress counts only completed rows. `open_enrollment_steps` lists the open
rows of active enrollments by due date; without `enrollments.read` it returns
the caller's assigned steps, and an assigned user can complete their step.

The `enroll` function keeps its signature: dates are set through
`set_enrollment_dates`, which the client's `enroll(program, subject, dates)`
calls after enrolling. Module programs (keys with a colon, such as
onboarding, sequences and courses) have no schedules. Adopted tables without
the five columns render without schedules.

## Consequences

- Overdue work is one indexed query on `due_at`, and rules, reminders and
  reports read the column like any other.
- Saving a program doesn't move running enrollments' due dates until the
  subject enrolls again or its dates change, matching the step snapshot of
  ADR 0077.
- Code that read every `enrollment_steps` row as a completed step must filter
  on `completed_at is not null`; the module's own functions do.
- Role assignees aren't resolved to users: `openSteps({ role })` lists a
  role's steps for whoever has `enrollments.read`.
