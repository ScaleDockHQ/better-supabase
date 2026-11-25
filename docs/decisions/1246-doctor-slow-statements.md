# 1246: Warn about slow statements from pg_stat_statements

- Status: accepted
- Date: 2026-11-25

## Context

The example harness measures database time per route, but only on the machine
that runs it. A deployed database has no such check, and a slow policy or SQL
function shows up only as a slow page.

## Decision

`doctor` gets the live check BS732. It reads `pg_stat_statements` for the API
roles (`authenticated`, `anon`, `service_role`) and `pg_stat_user_functions`
for the `public` and `better_supabase` schemas, and warns for each statement
with at least 5 calls and a mean of 100 ms or more. It reports nothing when
`pg_stat_statements` is not installed, and a saved snapshot skips it.

## Consequences

- A project sees its slowest real statements next to the other live findings,
  with the advice to run `explain (analyze, buffers)` under the same role.
- A fresh stack has no statistics, so the check cannot fail CI on an empty
  database.
- A function needs `track_functions` set to `pl` or `all` to be listed.
