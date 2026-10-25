# 0105: Verify RLS against the catalog and generate an access matrix

- Status: accepted
- Date: 2026-10-25

## Context

Doctor reads policies as text, and no test covers role by command by table, so a policy that
reads `true` or a missing `using` goes unseen.

## Decision

- `verifyCatalog(catalog)` checks facts: RLS on, force where needed, restrictive scope present, a
  write policy that is only `true`, `search_path` on definers, grants to `anon` and `PUBLIC`. The
  catalog comes from PGlite through `@supabase/lite` or from the live database. Doctor fails
  closed on an error finding.
- A generated access matrix has one pgTAP test per persona, command and table. The personas are
  anon, signed in without a membership, member of tenant A, member of tenant B, read-only support
  and the service role. A property test runs it over random projects.
- The same `Issue` type (ADR 0100) carries the findings.

## Alternatives considered

- Hand-written pgTAP per module: it covers what the author thought of.

## Consequences

CI time grows with the matrix; the matrix runs offline in PGlite and online in pgTAP.
