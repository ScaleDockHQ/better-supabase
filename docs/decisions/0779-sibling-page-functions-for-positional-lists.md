# 0779: Page through a sibling function when the list has positional arguments

- Status: accepted
- Date: 2026-11-13

## Context

ADR 0749 gave every list entity `page`, `facets` and `count` over one SQL list
function that takes `(tenant, filters jsonb)`. Lane G1 moved nine blocks that
already had that signature. Lane G4 covers the crm, people and scheduling
blocks, and most of their list functions take positional arguments
(`list_sequences(tenant, status)`, `list_passes(tenant, holder_user, subject_type,
subject_id, status, before, page_size)`). Replacing such a signature in place
breaks the generated migrations, the `supabase/schemas` copies, pgTAP tests and
every app that calls the function over RPC.

## Decision

An entity whose list function takes positional arguments keeps that function
unchanged and gains a sibling `page_<entities>(tenant, filters jsonb)` built
with the shared list template (`page_sequences`, `page_payroll_runs`,
`page_passes`, `page_enrollments`). `entityList` reads the sibling through its
`fn` option, and `list` keeps calling the old function. An entity whose list
function already takes `filters jsonb` (`list_prescriptions`) moves in place, as
in ADR 0749. Both forms declare `sorts`, `facets` and `filters` in
`src/blocks/<block>/lists.ts`, and `tests/blocks/list-surface.test.ts` keeps the
manifest and the SQL equal.

Lane G4 covers five entities: `sequence`, `payroll_run`, `pass`, `enrollment`
and `prescription`. `enrollments` also gains `get_enrollment` and `get`, because
it had no read by id. The other list entities of the three categories stay on
their own lists until a later lane: the blocks with extra columns (`contacts`,
`contracts`, `hiring`, `time-entries`, `bookings`, `qualifications`,
`medications`) need the row mapper of `fields` inside `entityList`, and `leave`,
`calendar`, `shifts`, `mail-sync` and the subject reads (`list_*_for_subject`)
carry their own permission or range rules.

## Alternatives considered

- Change the positional signatures to `(tenant, filters jsonb)`. Rejected: it
  breaks callers of a pushed function for a contract the sibling gives without
  a migration of their code.
- Add the new filters as more positional arguments. Rejected: a list filter is
  a list of values, which a scalar argument cannot hold.

## Consequences

Each converted entity has two SQL list functions until the old one is retired.
The two share the row JSON, so they cannot return different rows for the same
filters except where `list` still takes a scalar. Retire the positional
functions when a breaking SQL release allows it.
