# 0438: Name trigger-filled columns with a table tag

- Status: accepted
- Date: 2026-11-09
- Amends: 0102

## Context

`gen` leaves a not-null column optional on insert when it has a default, when a
trigger visibly fills a column a check keeps not null, or when
`tables.<t>.insertOptional` lists it. A trigger that fills a column in a way `gen`
cannot read (a function that writes it through dynamic SQL, or a trigger on a table
the app does not own) needed an entry in the config file, away from the table.

## Decision

`-- @bsb filled-by-trigger created_by owner_id` in a table's comment adds those
columns to the table's `insertOptional`. A column the config already lists is kept
once. Tables outside `config.schemas` are ignored, as for every table tag.

## Consequences

No module is rewritten and no data migration is needed. `gen` output changes only for
a table that carries the tag. A unit test covers the tag alone and merged with a
config entry.
