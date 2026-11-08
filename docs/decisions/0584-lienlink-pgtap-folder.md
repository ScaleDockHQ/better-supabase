# 0584: Hold the Lienlink projection shape with a pgTAP file

## Status

Accepted. Follows ADR 0471.

## Context

`tests/validation-lienlink` checks the declarative sync and doctor, but nothing asserts the shape ADR 0471 relies on: views over block tables, an `instead of` insert trigger, a stored generated column, a composite foreign key and app triggers beside the blocks'. A module change could drop one of them without a failing test, since the fixture's own files are the only place that says they exist.

## Decision

The fixture has `supabase/tests/projections.test.sql`, a hand-written pgTAP file of 16 catalog assertions. It is not a `900_better_supabase_` file, so `upgrade` never writes or removes it, and `copyFixture` does not copy it into the sync tests. The folder holds only this fixture's own tests, so a baseline refresh does not touch it.

## Consequences

`supabase test db` in the fixture's folder runs it against the stack built from the baseline migration (16 of 16 pass). It is not part of `pnpm test`, which needs no running stack.
