# 0428: Expose better_supabase.importing() to app SQL

- Status: accepted
- Date: 2026-11-08
- Amends: 0141

## Context

Block SQL guards a side effect with `ctx.importing()`, which renders
`better_supabase.import_run() is not null`. An app's own trigger or function had
no named way to ask the same question, so apps copied the expression.

## Decision

The prelude defines `better_supabase.importing()`, a stable `security invoker`
SQL function that returns `import_run() is not null`, executable by `anon`,
`authenticated` and `service_role`. Only the service role can begin an import
session, so a user session always gets false. `ctx.importing()` keeps its
expression; the function is for app SQL.

## Consequences

`better-supabase upgrade` rewrites the prelude in every project and the next
schema migration creates one function. No data migration. Nothing to measure: the
function is a name for an existing check.
