# 0346: Soft-deleted block rows carry archived_at

- Status: accepted
- Date: 2026-11-07
- Amends: 0246, 0247, 0345

## Context

Three block tables mark a soft delete with `deleted_at`: `drive_nodes`,
`memories` and `messages`. The convention of ADR 0246 calls the same state
`archived_at` everywhere else, and a restore clears it.

## Decision

- The three columns become `archived_at`. The rename is an explicit
  `column` row of `api/naming.json` per table, applied by `codemod naming` to an
  installed app and by the fixture migration
  `20261107222000_bsb_archived_at_names.sql`; a generated migration then
  replaces the functions that read them. The logical names (`deletedAt`) and
  the `Row` fields stay, so only `$client` and `queryRaw` see the new name.
- These stay `deleted_at`, and the catalog test counts them:
  - `auth.users.deleted_at`, which Supabase owns.
  - The organizations block's `deleted_at` with `deleteMode: 'soft'`: it
    records a deletion the data-lifecycle module can purge, not an archive.
  - The column an app table gets from `softDelete` (`deleted_at`,
    `APP_DELETED_AT_COLUMN`), `blocks.trash.options.deletedAt` and the
    `deleted-at=` tag. They name a column in the app's own schema, which the app
    renames when it wants to.
- An app that adopts its own messages, drive or memory table maps
  `deletedAt` in `columns`, as for any other column.

## Consequences

An app that reads one of the three columns over `$client` or `queryRaw`
changes the name.
