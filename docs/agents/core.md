# Core

Corrections for `packages/better-supabase/src/core` and the plugins.

## Column names and casing

Table metadata stores names in the configured casing: on a `casing: 'camel'`
table, `table.primaryKey`, `table.columns` and the keys of a row are
camelCase. PostgREST only knows the database names. Every name that goes into
a query (an order term, a filter, a select list, an `on_conflict` target)
passes through `builder.column(table, name)` first, as `withTieBreaker` and the
default order in `src/core/repository.ts` do. A raw `table.primaryKey` in an
`OrderTerm` sends `order=customerId.asc`, which PostgREST rejects.

The tests that catch this need a camel table whose primary key is not `id`
(`customer_tags` in the fixtures); a table keyed on `id` hides the bug because
the name is the same in both casings.

## Per-request work

`connect()` and the repositories run on every request. Work that depends only
on the schema or the plugin list (column maps, default orders, plugin hook
arrays) is computed once per table and cached in a `WeakMap` keyed on the
table or the plugin list, not rebuilt inside a method.
