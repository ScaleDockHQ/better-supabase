# 1257: Generated tag functions

- Status: accepted
- Date: 2026-11-26

## Context

ADR 1256 added `defineTags(tables)` as a runtime function, because the table
names were an app-written list. That list drifts from the schema: a new table
has no tag function until someone adds it, and a mistyped name still compiles.

## Decision

`tags()` from `better-supabase/generators/tags` writes `<output>.tags.ts`, one
`defineTags([...] as const)` call over the table keys of the model, sorted, with
`tables` to narrow it. The keys are the keys the cache invalidation uses
(`meta.tables`), so `tags.customers(org)` is the tag a mutation expires. The
generator follows the other built-ins: apiVersion 2, pure, worker safe, written
next to the main output.

## Consequences

- An app that lists `tags()` in `gen.generators` gets a typed `tags` object
  that follows the schema.
- The generated file imports `better-supabase/next`, like the generated
  hooks import the library.
- The example app does not use it yet: `gen` needs the local database, and the
  example's one-line cache files stay until its readers move to `tags`.
- Generated queries, `blockAction` actions and read sets stay out of this
  step; they need `gen` changes that touch every generated file.
