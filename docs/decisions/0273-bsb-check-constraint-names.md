# 0273: Name every generated check constraint bsb_*

- Status: accepted
- Date: 2026-11-07
- Amends: 0246, 0247, 0272

## Context

The catalog test of ADR 0247 counted 1,872 `better_supabase` check constraints
outside `bsb_*`. Postgres named nearly all of them (`<table>_<column>_check`),
and about twenty modules wrote a `drop constraint if exists <table>_<column>_check`
beside an `add constraint` of the same name, so the name was part of the SQL.

## Decision

- The renderer names each check a table statement leaves unnamed with the name
  Postgres would have chosen and `bsb_` in front: `bsb_<table>_<column>_check`
  for a check that reads one column, `bsb_<table>_check` for any other, and
  `1`, `2` after a clash within the table. It reads the statement in order,
  as Postgres does, so a name freed by a `drop constraint` can be taken
  again. A name past 63 bytes is cut at 54 bytes and takes a hash suffix.
- A check a module names itself gets the prefix wherever the name appears:
  `constraint`, `add constraint`, `drop constraint`, `validate constraint` and
  the `conname = '...'` test of a guard. A `drop constraint if exists` for a
  name the text never adds stays, because it removes a constraint an earlier
  release wrote. Because the pass runs after `staticDdl`, the merge of a named
  check into the inline check of the same table still sees the Postgres names.
- `appNameLengthError` no longer counts check names; the hash keeps two long
  names apart.
- `codemod naming` writes one loop over the catalog that renames every check
  of `better_supabase` and `workflow` to `bsb_<old name>`. The old names are
  the ones Postgres chose, which the SQL files never wrote, so the loop reads
  them from `pg_constraint`. The fixture migration
  `20261107180015_bsb_check_names.sql` is the same loop; no data moves and the
  second strict-coverage sync is empty, which shows the generated names equal
  `bsb_` plus the names the catalog held.

## Alternatives considered

Writing `constraint <name>` at each of the 1,872 sites in the module sources
would show the names, but it would repeat the Postgres rule by hand in every
module and leave the drop-and-add pairs to drift. One pass keeps the rule in
one place.

## Consequences

An app whose database numbered a clash differently (`_check1` created in
another order) sees the diff drop and add that one check on the next sync.
Names the loop skips (past 59 bytes) behave the same way.

Still open in the catalog test: 33 timestamp columns outside `_at`, 63
`organization_id` columns, and 31 `_user_id` or `deleted_at` columns.
