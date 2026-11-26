# 1251: SQL functions use the data verbs

- Status: accepted
- Date: 2026-11-26

## Context

The data verbs are `create`, `update`, `upsert` and `delete` (ADR 1250 and the
naming page). The SQL functions the modules install used `save_*` (131),
`add_*` (26) and `remove_*` (37) for the same writes, so a function name did not
tell a reader whether it inserted, updated or both, and it differed from the
repository method that calls it.

## Decision

The 196 module functions that spell a write with an old verb take the data
verb: `save_*` is `upsert_*`, `add_*` is `create_*` and `remove_*` is
`delete_*`. `load_ai_harness_session` and `read_field_values` are `get_*`. The
full list is the `sqlFunctionName` rows in `api/naming.json`, and
`src/sql/function-renames.ts` carries the same pairs for the doctor.

Each module function is dropped and created again by the next schema diff. It
is not renamed with `alter function`, because the plpgsql bodies qualify their
parameters with the function name, and it keeps no wrapper under the old name,
because a wrapper would keep both spellings in every grant list and every
catalog. The generated migration carries the grants. `better-supabase doctor`
reports an app's SQL that still calls an old name through the
`deprecatedSymbols` rule, and BS235 does not warn about a function that a
migration drops next to its new name. `better-supabase codemod naming` rewrites
`better_supabase.<old>` in app SQL and the whole-string names in TypeScript.

A few names keep their verb on purpose: `remove_promotion_code` (it detaches a
code from an order, not a delete) and every `set_*` function. Permission keys,
audit actions and event names do not embed a function name, so nothing in data
changes.

## Consequences

- Apps that call `better_supabase.save_*` directly rename the call before they
  apply the migration. Calls through the repositories and the typed clients
  need no change.
- `supabase/migrations/20270121000000_get_verbs.sql` and the two validation
  projects with their own migrations carry the drop and create.
- `scripts/check-naming.ts` fails when an old name returns outside history.
