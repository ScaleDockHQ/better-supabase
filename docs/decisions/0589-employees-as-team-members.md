# 0589: Keep employees and users in one team_members table

- Status: accepted
- Date: 2026-11-09

## Context

Apps that install `teams` and `employees` need teams with people who have no
account (technicians, drivers) next to users who have no employee record (an
owner, an external accountant). `team_members` keyed members on
`(team_id, user_id)`, and the access functions and policies read `user_id`.
Other adopters run `teams` without `employees` and must not see a change.

## Decision

With `employees` installed, `team_members` gets `employee_id`
(`columns.members.employee`, mappable to `null`), `user_id` becomes nullable
with a check that one of them is set, and the primary key becomes partial
unique indexes on `(team_id, user_id)` and `(team_id, employee_id)`. Without
`employees` the module renders as before, byte for byte.

`user_id` on an employee's rows follows `employees.user_id` while the user is
a member of the organization. A trigger the `employees` module writes on
`employees` sets it, merges a user-only row of the same team when an account
is linked, and adds a row for `employees.team_id`, the primary team. A
`before delete` trigger on `team_members` turns the cascades from `auth.users`
and the membership into `user_id = null` on a row whose employee and team
still exist. `team_ids_of` and the policies keep reading `user_id`.

`add_team_member` and `remove_team_member` take `employee uuid default null`
after `member`, and `list_teams` returns `member_employee_ids`. The teams data
file backfills `employee_id` and the primary teams for an app that adds
`employees` later.

## Alternatives considered

- A second table for employee members. Rejected: every read would union two
  tables, and a person with an account and an employee record would be on a
  team twice.
- Requiring an account for every team member. Rejected: the point is people
  without one.
- `on delete set null` on the user foreign keys. Rejected: a user-only row
  would then fail the check instead of going with its membership.

## Consequences

Access stays user-based, so RLS and `team_ids_of` don't change. An app whose
own `team_members` table is adopted drops its primary key and the `not null`
on the user column itself, because the schema diff never drops constraints of
an app table. The previous primary team's row stays when `team_id` changes.
Re-running the data file adds an employee back to their primary team after a
removal.
