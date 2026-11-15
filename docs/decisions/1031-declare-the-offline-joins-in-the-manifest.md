# 1031: Declare the offline joins in the manifest

- Status: accepted
- Date: 2026-11-15
- Amends: 0920, 0926

## Context

ADR 0926 let `EntitySurface.offline` state the scope, the extra conditions and the
system rows of a stream, and left out the streams that join to another table:
the notification events and preferences, the membership role sets and
organizations, and the attachment reader and subject rules (EX-1318). They stayed
written by hand in `src/cli/powersync/streams.ts`.

## Decision

`EntityOffline` gains `join`, a list of `EntityOfflineJoin` (additive, `apiVersion`
stays 1). Each entry has a `kind`: `owned` (rows with the user's `user_id`),
`referenced` (rows whose `column` is the `parentColumn` of a synced row),
`member-set` (the role set rows of the user's organizations), `member-organizations`
(the user's organizations, with the `select`ed columns), `readers` (hold the rows to
the organizations where the user's roles hold `read`) and `subject` (hold the rows
to the subjects the app registers for the types its view keeps). A join names its
table by the columns it declares (`EntityOfflineJoinTable`), as the generator found
it before, and `optional` skips it when the schema has no such table.

The notifications, memberships and attachments manifests declare their joins, and
`powersync streams` writes the streams from `offlineOf(block).join`. The
generated YAML is identical: a golden file written by the previous generator
guards it, and the existing manifest-versus-table test fails when the
declaration and `OFFLINE_RULES` differ.

## Alternatives considered

- Write the SQL of each join in the manifest: it would repeat the identifiers the
  generator resolves from the rendered files.
- Keep the joins in the generator: a block author could not see or change what a
  stream joins from the manifest.

## Consequences

Every offline stream of the eight blocks follows its declaration. A new join
shape needs a new `kind` (and a case in the generator), which is a change to a
versioned type. The three manifests grow by their join lists (the bundle
baselines are CI-measured).
