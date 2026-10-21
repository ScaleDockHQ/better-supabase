# 0063: Split the activity feed out of comments into its own block

- Status: accepted
- Date: 2026-10-21

## Context

The comments module carries the activity feed in `comments-activity.ts`:
`activity_entries`, `record_activity`, `list_activity`, the `activitySink`
and `activityListQuery`. The feed merges audit entries, notifications and
workflow runs and has nothing to do with comments. ADR 0062 moves comments
onto the messaging core and drops the `comments` table, so the feed would
otherwise ride along with a module it doesn't depend on, and an app that
wants a timeline without comments has to install comments anyway.

## Decision

Move the feed into an `activity` block: the SQL lives in
`src/sql/modules/activity.ts` and the TypeScript side in
`src/blocks/activity/`, with its own manifest, events, docs page and
subpath `better-supabase/blocks/activity`. The table, function and sink
names stay the same, so the move is a module change, not a data migration.
Presets that list `comments` and use the feed gain `activity`. The timeline
loader of the composition track (`loadTimeline`) builds on this block.

The split lands with the comments move (ADR 0062), in the same breaking
release, so apps update their block list once.

## Alternatives considered

- Keep the feed in comments. Comments become a thin layer on the messaging
  core, and the feed would be the only table left in that module.
- Put the feed in the audit block. The feed also merges notifications and
  workflow runs, and audit is append-only with a hash chain that the feed's
  rows don't need.

## Consequences

An app installs a timeline without comments, and comments shrink to the
messaging wrappers. Apps that read the feed through
`better-supabase/blocks/comments` change one import and add `activity` to
their blocks; the changeset lists both. We revisit if the feed grows a
dependency on comment rows that makes the split cost a join on every read.
