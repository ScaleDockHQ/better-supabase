---
"better-supabase": minor
---

Breaking: `custom-fields` gets `archiveDefinition` and `restoreDefinition`, and
the hard delete of a field definition is `purgeDefinition`, behind its own
`permissions.purge` key (it falls back to `custom_fields.manage`). An archived
field leaves `listDefinitions`, and `saveDefinition` and `setValue` refuse it
with `CUSTOM_FIELD_ARCHIVED`; its values stay and stay readable.
`listDefinitions` takes `{ entity, includeArchived }`, and a definition carries
`archivedAt`. The normalized layout has the column and functions; the inline and
keyed layouts have no definition rows.

| Before                               | After                                |
| ------------------------------------ | ------------------------------------ |
| `deleteDefinition(id)`               | `purgeDefinition(id)`                |
| `delete_field_definition(id)`        | `purge_field_definition(id)`         |
| event `field_definition.deleted`     | event `field_definition.purged`      |
| `list_field_definitions` with 2 args | a third argument, `include_archived` |

New events are `field_definition.archived` and `field_definition.restored`. Run
`better-supabase upgrade` and apply the migration. See the 0.66 to 0.67 guide.
