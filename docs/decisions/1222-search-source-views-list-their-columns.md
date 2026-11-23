# 1222: Search source views list the columns they read

- Status: accepted
- Date: 2026-11-23

## Context

A record type with `search.from` reads its title and body through a view. The
generator cannot see which columns of the record's table the view reads, so a
type without `search.columns` got `after insert or delete or update`, and every
update re-indexed the row. An adopter's view-backed types re-indexed on each
status change, timestamp bump and import write (feedback BS-06). `update of`
alone also fires when a statement sets a column to the value it already has.

## Decision

`search.columns` is required when `search.from` is set; the config error names
the record type. `triggerSql` in `src/sql/modules/search.ts` writes two row
triggers: `bsb_search_<type>_index` after insert or delete, and
`bsb_search_<type>_index_u` after `update of` the watched columns with a `when`
clause that compares each one with `is distinct from`. The statement-trigger
form (`search.statement`) is unchanged. The search block moves to version 6.

Doctor BS637 reads `information_schema.view_column_usage` and reports each
column of the record's own table that a source view reads and the list leaves
out, after the id, tenant and archive columns the trigger watches anyway.

## Alternatives considered

Parsing the view definition at `gen` time would infer the list, but the view is
app schema that changes after `gen`, and a live catalog read is what BS637
already does. Keeping the every-update default for a type without the list
keeps the cost the feedback reported, so the list is required instead.

## Consequences

On 1,000 rows of a view-backed type, an update of an unlisted column took 71 to
74 ms with 1,000 index trigger calls before, and takes 21 ms with none after
(`supabase/tests/scale/scale_search_view_updates.test.sql`). An app with
`search.from` and no list fails its config until it adds one. An app table file
that writes its own search trigger needs the same split.
