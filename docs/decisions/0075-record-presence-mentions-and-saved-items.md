# 0075: Put record presence, record mentions and saved items on the subject registry

- Status: accepted
- Date: 2026-10-22

## Context

Channels, comment threads and documents each want to show who has them open,
and each would otherwise define its own presence topic and policy. Messages
and comments want to mention a record (a deal, a customer) and the record
wants to list where it was mentioned. Members want to save a record or a
message for later with a reminder. All three are about a record, and the
subjects module already answers "may this user read this record"
(`can_subject`). Block entities register as subjects (ADR 0060), so a
conversation and a message are records too.

The reminders block keys one recurrence rule per tenant and record and
delivers each occurrence through a job. A saved item's reminder is one-off
and belongs to one member, so several members can save the same record with
different reminders.

## Decision

The subjects module adds Realtime policies for `presence:<type>:<id>` topics,
backed by `subject_presence_allowed(topic)`, which parses the topic, casts
the id to the subject's id type and calls `can_subject(type, id, 'read')`.
`better-supabase/realtime` exports `subjectPresence` and
`subjectPresenceValues(subject)` for `usePresence` and the bindings.

Messaging parses `@[Name](subject:<type>/<id>)` next to user mentions,
indexes the mentions of registered types in `messaging_record_mentions` on
send and edit, and lists them with `list_record_mentions`, which returns
nothing unless the caller reads the record and only messages in
conversations the caller reads. `mentionSegments`, `parseMentions`,
`recordMention` and `userMention` share one parser with comments'
`mentionsIn`.

The collections block keeps `saved_items` (member, record, note, `remind_at`,
`reminded_at`, `completed_at`) next to favorites, with `save_for_later`,
`list_saved_items`, `complete_saved_item`, `remove_saved_item` and the
service-only `remind_due_saved_items`, which claims due items with
`for update skip locked` and records `saved_item.reminded`. The TypeScript
`remindDue()` sends the configured notification through the `notifier` port,
the same shape the reminders block uses for its deliveries.

## Alternatives considered

- A presence topic per block (channels, comments, documents): three policies
  that each repeat the read check, and a fourth for the next block.
- Record mentions as a separate table per block: comments are messages since
  ADR 0062, so one index on messages covers both.
- Saved item reminders as reminders-block rules: the rule key is per tenant
  and record, not per member, and a one-off reminder needs no recurrence.
  Changing that key would break the reminders contract (`apiVersion: 1`).

## Consequences

Any registered record gets presence and backlinks without new SQL. Presence
states come from the clients, so apps show them as hints and never decide
access on them. Backlinks cost one insert per mentioned record on send and a
delete and insert on edit. Saved item reminders need a cron or jobs schedule
that calls `remindDue()` with the service role. If members need repeating
reminders on a saved item, revisit by letting the reminders block key rules
per member under a new `apiVersion`.
