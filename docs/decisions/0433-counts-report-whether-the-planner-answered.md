# 0433: Counts report whether the planner answered

- Status: accepted
- Date: 2026-11-09
- Amends: 0425

## Context

With the estimated default (ADR 0425) a total above 1,000 rows is the planner's
guess, but a caller could not tell it from an exact one, so a page could print
"12,300 results" for a figure that is off by thousands.

## Decision

- `ExecuteResult.capped` is `true` when the count is the planner's estimate (a
  `planned` count, or an `estimated` one past the threshold) and `false` when it
  is exact; it is absent when no count mode applies. The SQL executor sets it
  from the branch it took. The PostgREST executor infers it the way PostgREST
  counts: `planned` always, `estimated` above `max_rows` (1,000).
- `page.capped` carries it in an offset page that has a total, and
  `repository.counted()` returns `{ count, capped }`. `count()` still returns a
  number, so no caller changes.
- `formatPageTotal(page, { locale, capped })` renders the total, with `~` in front
  of an estimate unless the caller supplies the wording.

## Consequences

Additive: no module changes and no data migration. The root entry gains one small
function (`formatPageTotal`); the bundle test stays inside its slack. Unit tests
cover both executors, the repository, the page envelope and the formatter.
