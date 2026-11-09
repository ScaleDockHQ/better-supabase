---
"better-supabase": minor
---

Importing a meter reading that is below the previous reading of the same asset and unit stores the row with reason `import` and returns the warning `IMPORT_SERIES_DECREASE`. The guard still rejects a lower reading that has no reason. `tests.expect_import_warning` checks a batch result for a warning code.

`better-supabase upgrade` rewrites the assets module. The next schema migration adds `asset_meter_readings` and its functions. No data migration is needed.
