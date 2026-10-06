---
"better-supabase": minor
---

The data-lifecycle module covers tenant tables without listing them: `options.autoTables` (or `tables: "auto"`) adds every table in the listed schemas with the tenant column, and the user column when set, minus `exclude` globs, with explicit `tables` entries winning. The purge retries tables that another table still references, so their order no longer matters, and stops with `ORGANIZATION_PURGE_BLOCKED` when no pass makes progress. It deletes the organization row with an adopted organizations module too. `permissions.deletePlatform` lets platform staff request and cancel deletions, and `createDataExporter({ format: "csv" })` writes CSV files. `toCsv` lives in a shared block helper.
