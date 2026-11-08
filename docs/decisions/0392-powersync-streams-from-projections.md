# 0392: Generate PowerSync streams from the app's projection views

## Status

Accepted

## Context

The app owns views over block tables (ADR 0391), and clients read them. The PowerSync streams selected `*` from the block table, so the device held columns and rows the view hides, `membership_roles` synced only the user's own roles, the provider's version column reached the device, and a bigint id synced as a number.

## Decision

`better-supabase powersync streams` reads the app's schema files. `projectionsOf` finds each view that selects plain columns (with optional aliases and a `where`) from one table; a stream over that table lists the view's columns under the view's names and adds the view's `where`. The client `Table` takes the same columns. A stream that already lists its columns (organizations) is left alone. Any stream drops a column named `authz_version`, `authz_ver`, `permissions_version` or `permission_version`, sends a bigint `id` as text, and keeps a table's own `id` instead of the composite one. `membership_roles` is bounded by the user's organizations and has no user or disabled filter. Doctor BS381 flags the helpers (`createNativeClient`, `powersyncEngine`, `attachmentQueueRoute`, `queryEngine`) when they name a projected block table, and BS382 fails a `subjects.<type>` entry that disagrees with the table's `@bsb subject` comment. `gen.powersync.instances` already decides which instances stream, so no stream appears because a block is installed.

## Consequences

A stream and its view select the same columns, except that a table keyed by two columns streams a composite `id` the view lacks; `tests/validation-lienlink` checks both against the snapshot's view columns.

Not done: moving the generated data hooks and block clients from the block table to a view named after the instance, child streams that join an app parent subject, and subject-scoped streams beyond the view's `where`. The first needs the typed client to tell an instance property from a view of the same name; the others need the app's parent subjects, which the generator reads only from `@bsb subject` tags.
