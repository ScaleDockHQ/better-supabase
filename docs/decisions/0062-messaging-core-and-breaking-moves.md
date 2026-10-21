# 0062: Build one messaging core and move comments and the inbox onto it

- Status: accepted
- Date: 2026-10-21

## Context

Three surfaces hold messages, and each has its own tables: `comments` (with
`comments-writes.ts` and its own mention, reaction and activity code), the
inbox's `conversations` and `inbox_messages` (with a jsonb `attachments`
array that skips the scan gate and its own `conversation_reads`), and a team
chat block that the collaboration roadmap needs next. Every feature the SaaS
products share across all three (threads, unread markers, edits, pins,
attachments, reactions, typing, follows) would be built three times.
`reactions.ts` already carries hand-written subject cases for `comment` and
`inbox_message` because those rows are not entities.

ADR 0060 made block entities renameable and registered them as subjects, so
a module that declares `message` as an entity gets attachments and reactions
on messages without a hard-coded case. The package is pre-1.0 and the user
approved breaking changes for this track.

## Decision

Add a `messaging` SQL core (`src/sql/modules/messaging.ts`, split into
`-names`, `-tables` and `-functions` files) that owns `conversations`,
`messages`, `message_edits`, `conversation_members` and `thread_reads`.
A conversation has a `kind`: `channel`, `dm`, `group_dm`, `subject` (bound to
one record through `subject_type` and `subject_id`) or `inbox`. Messages keep
a thread summary through a trigger, and threads default to one level of
replies (`threadDepth: 1`, with `"unlimited"` as an option).

- **Entities:** the core declares `conversation` and `message` (primary) in
  `NAMES.entities`, each a subject, so attachments and reactions accept
  messages and a rename (`message` to `post`) renames the subject too.
- **Who may do what:** each conversation kind asks its owning block through
  a `can_conversation` hook, so the core never names channels, comments or
  the inbox.
- **Channels first:** the `channels` block ships on the core before anything
  moves, with channels, DMs, record channels, typing and scheduled send.
- **Comments move (breaking):** comments become one `subject` conversation per
  record, created on the first comment. The `comments` table and
  `comments-writes.ts` go; the comment functions become wrappers over, or
  renames of, the messaging functions; `comment.*` events become `message.*`
  with `conversationKind: "subject"`.
- **The inbox moves (breaking):** inbox conversations and messages become
  kind `inbox`, internal notes become messages with `kind: "note"`,
  `conversation_reads` becomes `conversation_members.last_read_at`, and
  inbound files become scanned `attachments` rows instead of a jsonb array.
  The inbox keeps its own contacts, deliveries, inbound events, templates
  and membership.
- **Upgrade path:** `sql upgrade` learns to rename installed tables and to run
  the column moves a module declares in `NAMES.migrations`. Each breaking
  phase ships a data migration on top of that, an entry in the 0.9 to 0.10
  upgrade guide and a changeset with an old-to-new name table.

## Alternatives considered

- Keep three sets of tables and share code through helpers. Every feature
  still needs a migration per surface, unread state stays three different
  shapes, and reactions keep their hand-written cases.
- Build channels on the inbox tables. The inbox models external contacts and
  deliveries; team chat has neither, and comments would still be separate.
- Keep the old comment functions as deprecated aliases. Two code paths over
  one table set cost more than one rename table in a pre-1.0 changeset, and
  doctor can flag apps that still call the removed functions.

## Consequences

Threads, read markers, edits, pins, attachments, reactions, typing and
follows are built once and reach chat, comments and the inbox together.
Adopters that use comments or the inbox (CentraKit among them) must run the data migration and update their calls; each breaking
phase writes those steps into a prompt for them. The shared SQL changes in
every early phase, so the pg-delta round trip, the golden files and
`tests/validation-centrakit` are refreshed in each pull request. We revisit
the single-core shape if a conversation kind needs storage the core can't
express without nullable columns that only one kind uses.
