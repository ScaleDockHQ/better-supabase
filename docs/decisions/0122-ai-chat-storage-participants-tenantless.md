# 0122: Let ai-chat run without a tenant, share chats with participants and store native parts

- Status: accepted
- Date: 2026-10-28
- Amends: [0010](0010-neutral-blocks-and-sdk-adapters.md)

## Context

The `ai-chat` block assumed every chat lives in a tenant, belongs to one user
and stores a branching tree of canonical parts keyed by text ids. Apps built
on the AI SDK asked for three things it couldn't do: a personal assistant
with no organization, a chat that a few people read or write together, and a
plain message list keyed by uuid that keeps the `UIMessage` parts the SDK
sends, with no converter in between. Each of them also wanted their own
columns on the block's tables, not only on `ai_chats`.

## Decision

`blocks["ai-chat"].options.tenant: false` makes `organization_id` nullable on
`ai_chats` and `ai_projects`. A row without a tenant is its owner's alone: any
signed-in user may create one, it can't be shared with an organization
(`AI_CHAT_NO_TENANT`), and the AI SDK adapter skips the quota and the `org:`
gateway tag for it. A row with a tenant keeps the tenant permissions and the
restrictive `bsb_tenant_scope` policy (ADR 0099).

`ai_chat_participants` holds the viewers and editors of a chat besides its
owner. Viewers read; editors also send messages, stop a reply and switch
branches. The owner adds people (with `ai_chat.share` in a tenant chat), and
each user message records its writer in `ai_messages.author_id`. Because the
read and write functions are security definers that skip RLS, they check a
participant's membership themselves: in a tenant chat a participant counts
only while they belong to the tenant, and `add_ai_chat_participant` refuses
someone who can't hold `ai_chat.read` there.

`options.messages` chooses the message table's shape once, at install:
`key` (`text` or `uuid`) types the id and every column that points at a
message, `tree: false` drops `parent_id` for one list per chat ordered by
`seq`, and `parts: "native"` stores the SDK's own message as the row's parts
with `format` `native`. This amends ADR 0010: the canonical format stays the
default and the only one search and memory are written against, but an app
may opt out of it for a chat table that one SDK owns end to end. The block
still imports no SDK, and the adapter still owns no table.

Every ai-chat table takes extra columns through its own option
(`projectExtraColumns`, `participantExtraColumns`, `messageExtraColumns` and
so on), written through the client's `fields` and returned under `fields`.

## Alternatives considered

A personal tenant per user would have kept the column required, but creates
an organization the app never shows and doubles the rows a sign-up writes.
Sharing through the share-link table would have reused one table, but a link
is anonymous and read-only, while a participant is a person who can write.
Keeping the converter and adding a raw column for native parts would have
stored every message twice; apps that chose native parts never read the
canonical copy.

## Consequences

`organizationId` is optional on chat, project and moderation records, and
`AssistantContext.organizationId` is `string | null`, so app code that read it
as a string changes. A chat with native parts depends on the SDK's message
shape, and moving it to another SDK is a data migration. The key and the
shape can't change on an existing install without moving the rows. A uuid
key needs uuid ids from the client (`generateId: () => crypto.randomUUID()`).
