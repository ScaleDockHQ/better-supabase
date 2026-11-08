---
"better-supabase": minor
---

The `time-tracking` block is `time-entries`. Import from `better-supabase/blocks/time-entries`, name it `blocks["time-entries"]`, and use `db.$blocks.timeEntries`. Run `better-supabase codemod naming` to rewrite imports and the config key, then `upgrade`; the migration renames the block's registry row and its permission keys in place, so roles and overrides keep their grants.

| Old                                                             | New                                                          |
| --------------------------------------------------------------- | ------------------------------------------------------------ |
| `better-supabase/blocks/time-tracking`                          | `better-supabase/blocks/time-entries`                        |
| `blocks["time-tracking"]`                                       | `blocks["time-entries"]`                                     |
| `createTimeTracking`, `timeTrackingBlock`, `timeTrackingEvents` | `createTimeEntries`, `timeEntriesBlock`, `timeEntriesEvents` |
| `TimeTracking`, `TimeTrackingOptions`, `TimeTrackingEvents`     | `TimeEntries`, `TimeEntriesOptions`, `TimeEntriesEvents`     |
| `time_tracking.read`, `.track`, `.approve`, `.manage`           | `time_entries.read`, `.track`, `.approve`, `.manage`         |
