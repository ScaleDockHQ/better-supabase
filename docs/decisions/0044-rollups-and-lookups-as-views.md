# 0044: Rollups and lookups render as a `security_invoker` view

- Status: accepted
- Date: 2026-10-18

## Context

No-code database builders (Airtable, Baserow, NocoDB, Notion) let a table
show values computed from linked rows: a count of a project's open tasks, the
sum of an invoice's lines, the name of a task's project. Their formulas are
free text that the builder evaluates. better-supabase app tables (ADR 0040)
had only stored columns, so an app wrote these as SQL by hand, or computed
them in TypeScript after reading every child row.

A computed value must respect row level security: a rollup that counts rows
the caller can't read leaks them. A design rides on a URL (ADR 0040), so any
SQL it carries runs on whoever deploys it.

## Decision

An app table takes `rollups` and `lookups`, both keyed by the new column's
name and built from structured keys only:

- A rollup is `{ table, via, aggregate, column?, where? }`: `count`, `sum`,
  `min`, `max` or `avg` over the app table `table` through its reference
  column `via`, optionally only the rows whose select column equals one of
  its options.
- A lookup is `{ via, column }`: a column of the app table that the
  reference column `via` points at.

`resolveConfig` checks every name against the tables, the reference and
the column types, and lists the valid choices when one is wrong. There is no
free SQL anywhere in the keys.

`sql sync` renders `public.<table>_view` with `security_invoker = true`: the
table's columns, then one `left join lateral` subquery per rollup or lookup.
The view reads every table with the caller's row level security, so a rollup
counts only rows the caller can read. Only `authenticated` and
`service_role` can read it. The lateral joins make Postgres treat the view
as not automatically updatable, so `gen` types it as a read-only model with
no special case. The view keeps no data, so the schema file drops and
creates it on every sync. The pgTAP file checks that it exists, runs as the
invoker, has no `anon` grant, and shows no rows to a signed-in stranger.

## Alternatives considered

Stored columns kept up to date by triggers would read faster, but they can
drift and need a backfill. Each trigger also runs as its owner, so it could
count rows the editor can't read. A `security definer` function would hide
rows the same way. Free formula text would match the builders, but a design
link would then carry SQL to whoever opens it. A materialized view needs a
refresh schedule and can't apply the caller's row level security.

## Consequences

A design that uses `rollups` or `lookups` writes design format 3. Older
releases reject it with a message to update. Each rollup runs one subquery
per row read from the view, so a list of many rows with many rollups should
page. The child's reference column already has an index. Adding or removing
a computed column is a safe change in `design-diff`, because the view keeps
no rows. An app that needs a formula the keys can't express writes its own
view.
