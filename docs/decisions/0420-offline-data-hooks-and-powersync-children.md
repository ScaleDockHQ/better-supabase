# 0420: Pause data hooks and record pages offline, and stream child tables with their parent subject

- Status: accepted
- Date: 2026-11-08
- Amends: 0344, 0392, 0393

## Context

ADR 0344 paused the block controllers offline and left the record and list
controllers in `src/react` out. ADR 0392 and ADR 0393 left child PowerSync
streams, attachment streams scoped beyond the view's `where`, and
`positionalTeamWrites` as deferred work.

## Decision

The data controllers (`createDataList`, `createDataOne`) and
`createRecordController` take an `offline` option and expose `setOffline`, with
the state field `offline` optional, as in ADR 0344. A paused read keeps the last
data and shows no error, a read that fails while offline waits for the next
reconnect, and a data write keeps its optimistic row and runs on reconnect (all
held writes run, because two writes to different rows are not one write). A
`RecordProvider` queues one write per binding and write name, as a block
mutation does. An engine with `connect` (a local database) never waits.

The hooks read `OfflineContext` from `src/react/offline.ts`, a context that is
`false` until set. `OfflineBoundary` in `better-supabase/next/offline` sets it
from `useOffline()`. The binding to Next.js stays in that subpath and only
creates a context element, so the next-build baseline does not move; the
controllers and the context live in the framework-agnostic modules.

`powersync streams` reads `@bsb subject` tags from the app's schema files. An
attachments stream whose view keeps one `subject_type` also keeps only the files
of that subject's rows in the user's organizations. `gen.powersync.children`
lists app tables (`table`, `parent`, `column`) that stream with a parent
subject: the rows whose column holds the id of a parent row in the user's
organizations. Their columns come from the snapshot.

`positionalTeamWrites` is not a flag in the code: the teams client takes an
object (`addMember({ teamId, userId })`) and so does the route, so there is
nothing to remove. The mentions in ADR 0393, the migration guide and the 1.0
changeset describe work that was never needed and go when the release notes are
next edited.

## Alternatives considered

Putting the data and record hooks in `better-supabase/next/offline` would have
bundled the record machinery into that entry and raised its size baseline. A
`@bsb powersync-child` tag instead of the config key needed a new table feature
in the SQL generator for one option. Gating a local engine's reads would have
stopped the device's own database from answering offline.

## Consequences

The Playwright spec `tests/offline.spec.ts` in the example app covers the
banner and a loaded list, and needs the local stack to run. The
`tests/validation-lienlink` fixture has no `job_parties` table yet: adding one
needs a new baseline migration and snapshot, so the child stream is held by unit
tests and the command test. A parent with several subject types in one view is
not scoped.
