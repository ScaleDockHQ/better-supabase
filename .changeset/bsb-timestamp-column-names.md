---
"better-supabase": minor
---

Every timestamp column a block adds ends in `_at`, with one explicit new name per column. Run `better-supabase codemod naming` to write the migration that renames the columns of an installed app; no data moves, and the `upgrade` after it replaces the functions that read them. `recurrence_rules.dtstart` and `maintenance_plans.dtstart` keep the name RFC 5545 gives them.

| Old                                                   | New                                                                  |
| ----------------------------------------------------- | -------------------------------------------------------------------- |
| `locked_until`                                        | `lock_expires_at`                                                    |
| `leased_until`, `lease_until`                         | `lease_expires_at`                                                   |
| `snoozed_until`, `paused_until`, `claimed_until`      | `snooze_expires_at`, `pause_expires_at`, `claim_expires_at`          |
| `dispatch_until`, `publish_until`, `legal_hold_until` | `dispatch_expires_at`, `publish_expires_at`, `legal_hold_expires_at` |
| `scheduled_for`                                       | `scheduled_at`                                                       |
| `window_start`, `bucket_start`, `original_start`      | `window_started_at`, `bucket_started_at`, `original_starts_at`       |
| `purge_after`, `not_before`, `effective_from`         | `purge_at`, `not_before_at`, `effective_at`                          |
| `failing_since`, `missing_since`                      | `first_failed_at`, `went_missing_at`                                 |
| `subject_updated_at_at_import`                        | `subject_imported_updated_at`                                        |
| `valid_from`, `valid_until` on passes and prices      | `starts_at`, `expires_at`                                            |
| `valid_until` on consents                             | `expires_at`                                                         |
