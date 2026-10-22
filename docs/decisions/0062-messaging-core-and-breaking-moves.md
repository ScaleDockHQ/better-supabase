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

## Amendment: the core as built (phase 1c)

- **Access is a column, not a hook.** A conversation's `access` is
  `members`, `tenant` or `subject`, and `can_conversation` reads it: members
  only, everyone with `messages.read` in the tenant, or whoever passes
  `can_subject` for the linked record. Channels, comments and the inbox fit
  these three, so no block needs to answer a hook on every read, and the
  read policies stay plain SQL. A kind that needs another rule adds an
  `access` value in its phase.
- **The inbox renames to coexist.** Until phase 4 moves it onto the core, the
  inbox's `conversations` table is `inbox_conversations` and its six
  colliding functions take an `inbox` infix (`send_inbox_message`,
  `list_inbox_conversations`). The inbox module's version 3 upgrade renames
  the table and drops the old functions; the fixture does the same in a
  hand-written migration, since pg-delta can't see a rename.
- **Replies flatten.** With `threadDepth: 1`, a reply to a reply joins the
  root's thread with the root as its parent.
- **Record mentions are parsed, not acted on.** `parse_mentions` returns
  `@[Title](subject:<type>/<id>)` mentions next to users and `@channel` or
  `@here`; checking them against the subject's permission waits for the
  record mentions phase.

## Amendment: the channels block as built (phase 1c)

- **A channel is a row next to its conversation.** The `channels` table holds
  the name, visibility, topic, purpose and linked record, keyed by the
  conversation id. Membership, archiving, typing and read markers stay in
  messaging, so `archived_at` is read from the conversation and a channel's
  `id` works with every messaging call and hook.
- **Visibility maps onto access.** A public channel is a `tenant`
  conversation and a private one a `members` conversation, so the core's
  access rule decides who reads, joins and invites. A private channel a
  caller can't read looks the same as one that doesn't exist (`P0002`).
- **Direct messages stay in the core.** `openDirect` already opens one
  conversation per set of people, so channels adds no DM functions.
- **No `extraColumns` yet.** App columns go on messages through the core.
- **Hooks live in messaging.** `useMessages` and `useConversations` come from
  `better-supabase/blocks/messaging/react`, since channels, comments and the
  inbox share them. They are not named `useConversation`, which the inbox
  hooks own until phase 4.
