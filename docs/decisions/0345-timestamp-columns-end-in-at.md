# 0345: Timestamp columns end in _at

- Status: accepted
- Date: 2026-11-07
- Amends: 0246, 0247

## Context

The catalog test of ADR 0247 counted 33 `timestamptz` columns outside `_at`:
`locked_until`, `scheduled_for`, `purge_after`, `valid_until` and the like. A
reader could not tell an instant from a date or a duration by the name.

## Decision

- Each column gets an explicit new name, written as a `column` row in
  `api/naming.json` with its table. The rename is not a suffix rule, because
  `valid_from` and `valid_until` are dates in `tax`, `funding` and `quotes`.
  The SQL, the registry defaults, the TypeScript readers, pgTAP files, docs and
  goldens use the new names.
- `*_until` and `*_since` become `*_expires_at`, `*_started_at` or
  `first_*_at` by what they mean: `lock_expires_at`, `lease_expires_at`,
  `snooze_expires_at`, `pause_expires_at`, `claim_expires_at`,
  `dispatch_expires_at`, `legal_hold_expires_at`, `publish_expires_at`,
  `first_failed_at`, `went_missing_at`. The windows of a pass, a price and a
  consent are `starts_at` and `expires_at`. Other renames: `scheduled_at`,
  `window_started_at`, `bucket_started_at`, `original_starts_at`, `purge_at`,
  `effective_at`, `not_before_at`, `subject_imported_updated_at`.
- Exceptions, which the catalog test counts: `recurrence_rules.dtstart` and
  `maintenance_plans.dtstart` keep the name RFC 5545 gives the property. The
  `valid_from` and `valid_until` date columns stay.
- `codemod naming` renames the columns of an installed app, when its SQL files
  name the old column, and the fixture migration
  `20261107180016_bsb_timestamp_column_names.sql` does the same; a generated
  migration then replaces the functions that read them. The second strict
  coverage sync is empty.

## Consequences

An app that reads a column over `$client` or `queryRaw` with the old name
changes it. The public `Row` fields keep their camel case names.
