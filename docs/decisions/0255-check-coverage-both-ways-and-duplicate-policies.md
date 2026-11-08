# 0255: Check coverage in both directions and report duplicate policies

- Status: accepted
- Date: 2026-11-07
- Amends: 0251

## Context

`supabase db schema declarative sync --strict-coverage` fails for an object the
database has and the schema files lack. Doctor had no rule for that, none for
the opposite case (a file that no migration backs yet), none for two policies
that say the same thing, and `upgrade --check` only looked for helpers the
prelude defines twice.

## Decision

Doctor gets three rules, all in `src/cli/doctor/ownership.ts`:

- BS375 reports policies on one table with the same command, roles and
  expressions under different names. `parseDeclared` records each policy's
  table and the text after it, and `duplicatePolicies` groups them.
- BS376 and BS377 compare the tables, views, types and functions that the
  migrations create with those the schema files declare, under pg-delta only.
  Supabase's schemas and objects a later migration drops are left out.

`upgrade --check` runs the file-level checks that apply to the installed block
files: a prelude helper defined twice, an object two block files declare,
`transaction=false`, a top-level `insert` and duplicate policies. Its result
data lists them under `problems`, which replaces `duplicated`.

## Alternatives considered

Running every doctor rule from `upgrade --check` would fail apps over findings
in their own files, such as `if not exists` in an app table, that `upgrade`
cannot fix.

## Consequences

The CentraKit and Lienlink fixtures pass `upgrade --check`. Migrations that
rename an object report it under BS376 and BS377 until the rename is a drop and
a create, so a rename ships as a reviewed hand migration, as ADR 0250 says.
