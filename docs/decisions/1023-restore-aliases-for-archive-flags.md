# 1023: Restore aliases for archive flags

- Status: accepted
- Date: 2026-11-14

## Context

ADR 0839 pairs every `archive` with a `restore`. It left the blocks whose
`archive` already takes an `archived` flag for a later slice. Those SQL
functions (`archive_deal`, `archive_work_item` and `archive_work_items`,
`archive_conversation`, `archive_channel`, `archive_collection`,
`archive_accounting_account`) un-archive with `archived: false`, so the row
could come back, but the client had no `restore` and no event told a sink.

## Decision

The flag stays. The client gains `restore`, which calls the same SQL function
with `archived: false`, and the SQL function records `<entity>.restored` when
it clears an `archived_at` that was set. Restoring a record that is not
archived records nothing. `archive` and `restore` need the same permission, as
in ADR 0839.

| Block         | New client method     | New event                        |
| ------------- | --------------------- | -------------------------------- |
| `deals`       | `restore`             | `deal.restored`                  |
| `tasks`       | `restore` (id or ids) | `task.restored`                  |
| `messaging`   | `restore`             | `conversation.restored`          |
| `channels`    | `restore`             | `conversation.restored`          |
| `collections` | `restore`             | `collection.restored`            |
| `accounting`  | `restoreAccount`      | none (accounts record no events) |

`teams` and `legal-entities` already had a restore, so they are unchanged.
Facilities reuses the task SQL, so it records `maintenance_request.restored`.

## Alternatives considered

A separate `restore_*` SQL function per entity (ADR 0839's reference types)
adds a security definer function, a registry entry and a grant for each block
and repeats the archive's lookup and permission check. The flag already has
the behavior, so only the event and the name were missing.

## Consequences

No new SQL function names and no new permission keys, so the practices
baseline is unchanged. The migration replaces five functions. Apps that read
the event catalog see four new event types. No existing call changes, so this
slice is not breaking.
