---
"better-supabase": minor
---

New `observations` block (`better-supabase/blocks/observations`): coded measurements of any record, such as vital signs.

- A definition has a value type (`number`, `integer`, `boolean`, `code`, `text` or `components`), a UCUM unit, a code and valid, reference and critical ranges. `options.defaults: "vitals"` installs nine system definitions with their LOINC codes; `saveDefinition` adds an organization's own or overrides a system one.
- `record` and `recordMany` refuse a value outside the valid range and flag it `normal`, `low`, `high`, `critical_low` or `critical_high`. A critical value emits `observation.critical` and notifies the leads of the record's team.
- `amend` records a correction and marks the original `amended`; `markError` marks one `entered_in_error`. `ingest` takes device or import readings with the service role and skips an `externalId` it has seen.
- `list`, `latest`, `series` and `buckets` (per UTC hour, day, week or month) read a record's values. With the forms block, a field with `meta.observation` records an observation when a form about a record is submitted, and the forms field schema takes `meta`.
- `options.partitioned` partitions the observations table by month. The permission keys are `observations.read`, `observations.record` and `observations.manage`; the default member role reads and records.
- The `observation-chart` UI recipe renders a record's latest values with their flags and a sparkline.

Add `observations: {}` to `blocks`, run `better-supabase add observations` and generate a migration.
