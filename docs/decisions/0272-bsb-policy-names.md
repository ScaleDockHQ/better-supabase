# 0272: Name every generated policy bsb_*

- Status: accepted
- Date: 2026-11-07
- Amends: 0246, 0247, 0271

## Context

The catalog test of ADR 0247 counted 478 `better_supabase` policies outside
`bsb_*`: block modules named them `<table>_read` and similar, while the
policies on an app's table and the tenant scope already carried the prefix.

## Decision

- The renderer prefixes every policy a module creates with `bsb_`, in the
  `create`, `alter` and `drop` statements alike, after the pass that names a
  block's policies on the app's own tables (`bsb_<table>_<command>`). A name
  past 63 bytes is cut at 54 bytes and takes a hash suffix, as the other
  generated names do. A `drop policy if exists` for a name the file never
  creates stays, because it removes a policy an earlier release wrote.
- `bsbPolicyName()` in `better-supabase/sql` is the one function that maps a
  module's policy name to the generated one.
- `codemod naming` reads the `create policy` statements of the project's SQL
  and writes one `alter policy ... rename to` behind an existence check for
  each `better_supabase` policy that lacks the prefix. The rule replaces 478
  rows in the rename table.
- The fixture migration `20261107180014_bsb_policy_names.sql` renames the 478
  policies of the local database; no data moves and the second
  strict-coverage sync is empty. `naming_catalog.test.sql` allows no policy
  outside `bsb_*`.

## Alternatives considered

Renaming at each of the roughly 480 `makePolicy` call sites and 73 `drop
policy` sites keeps the names visible in the module source, but a new module
could still forget the prefix. One pass over the rendered text makes a
missing prefix impossible.

## Consequences

Still open in the catalog test: 1,872 check constraints that Postgres names
itself, 33 timestamp columns outside `_at`, 63 `organization_id` columns, and
31 `_user_id` or `deleted_at` columns.
