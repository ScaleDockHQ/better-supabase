# 1083: Archive and restore a field definition (lane Y2, slice 10)

- Status: accepted
- Date: 2026-11-15
- Amends: 1052

## Context

ADR 1052 gives the field definition an archive. `delete_field_definition`
removes the definition, and the foreign key from `field_values` removes every
value anyone entered under it, on every record. Retiring a field that people
no longer fill in therefore costs the history of that field.

## Decision

`archive_field_definition` and `restore_field_definition` need the manage key,
record `field_definition.archived` and `field_definition.restored` once, and
return the definition unchanged when it already is in the target state.

- The definitions table gains an optional `archived_at` column, and
  `list_field_definitions` reports it as `archivedAt`.
- `list_field_definitions` hides archived fields by default and takes
  `include_archived` as a third argument, so the migration drops the two
  argument form.
- `save_field_definition` and `set_field_value` refuse an archived field with
  `CUSTOM_FIELD_ARCHIVED` (SQLSTATE 55000). `read_field_values` still returns
  its values, so history stays visible.
- `delete_field_definition` becomes `purge_field_definition` and
  `field_definition.deleted` becomes `field_definition.purged`. Purging needs
  `permissions.purge`, falling back to the manage key, because it removes the
  values of every record.
- The inline layout has no definition rows and the keyed layout stores the key
  and label on the value row, so neither gets an archive.

## Consequences

Breaking for callers of `deleteDefinition` and for sinks that match
`field_definition.deleted`; the changeset and the 0.66 to 0.67 guide have the
old-to-new table. A custom definitions table without `archivedAt` gets neither
function and keeps the two argument list.
