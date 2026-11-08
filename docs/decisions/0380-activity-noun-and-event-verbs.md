# 0380: Engagements are activities, and events use the lifecycle verbs

- Status: accepted
- Date: 2026-11-08
- Amends: 0090, 0246, 0374

## Context

The activities block kept the old `engagement` noun in its tables, columns of
other blocks, functions, hint codes, types and options, and the naming engine
renamed it on the way out. With `spec.formerly` gone (ADR 0374) the source has
to say the noun itself. Three events used `saved` and `removed`, which the
naming convention does not list.

## Decision

- Every `engagement` in the activities, mail-sync and bookings modules, their
  clients, types, hint codes (`ACTIVITY_NO_TRANSCRIBER`), the
  `activities.transcribe` queue and the `mail-sync` option `activityType` is
  `activity`. The tables are `activity_subjects`, `activity_recordings`,
  `activity_notes` and `activity_transcript_segments`, with their constraints,
  indexes and policies. `20261108050000_bsb_activity_names.sql` renames them;
  the `codemod naming` rows do the same for an installed app.
- `vex_statement.saved` is `vex_statement.updated`, `team_member.removed` is
  `team_member.deleted` and `reaction.removed` is `reaction.deleted`, each as
  an `event` row of `api/naming.json`.
- `Growth & engagement` stays: it is a catalog category, not the noun.

## Consequences

An app that reads an `engagement_*` table over `$client` or `queryRaw`, listens
for one of the three events or imports `Engagement*` types changes the name.
Outbox rows already written keep their old event type.
