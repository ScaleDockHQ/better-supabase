---
"better-supabase": minor
---

App tables get record history with per-field restore, upsert imports and a bulk set action.

- `appTables.<name>.subject.versions` (`true` or `{ columns, auto }`) registers the table with the versions block, so its rows get snapshots without an entry in `subjects`. It needs the versions block, and a design with `versions` is format 4. A change to it is the safe design change `table.versions`.
- `versions.restoreFields(id, fields)` writes back only the named fields. It fails with `VERSION_FIELDS_EMPTY`, `VERSION_FIELD_UNKNOWN` or `VERSION_RESTORE_UNSUPPORTED`.
- `appTableImport` builds an import keyed on one of the table's unique sets that updates existing rows (`update: "fill"` or `"overwrite"`), and `previewImport` counts the rows it would create, change and leave unchanged.
- The bulk action `appTables.set` sets columns on the selected rows through `app_table_set`, as the caller. A row fails with `APP_TABLE_SET_EMPTY`, `APP_TABLE_SET_COLUMN`, `APP_TABLE_SET_SUBJECT` or `APP_TABLE_SET_NOT_FOUND`.
- New recipes: record history and upsert import.
