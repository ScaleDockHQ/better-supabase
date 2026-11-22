# 1162: Label messages with the actor

- Status: accepted
- Date: 2026-11-21

## Context

ADR 1114 labelled claims and task events with `{ kind, name }`. Comments and timeline entries come from messaging, where only the author id was stored, so an agent's comment looked like the user's. The timeline already reads `actorKind` and `actorName` from event payloads.

## Decision

Messaging gains the optional columns `author_kind` and `author_name`. `send_message` takes `attrs.actor` and fills them the way `task_actor` does (`src/sql/modules/actor-label.ts`): the profile's own kind when it is a short lowercase word, `agent` for a token with an `act` claim of that kind, `service`, `system` or `user`. `message.sent` and the other message events carry `actorKind` and `actorName` when the columns exist. `NewMessage` and `NewComment` take `actor`, and `Message` returns `authorKind` and `authorName`.

The columns follow ADR 0325: a managed table creates them, and an app table gets them from its block-columns file (`add column if not exists`), so an adopted table that doesn't declare them keeps working and the label is absent. The module version is 2 with a no-op upgrade step, because the statements are idempotent. The label never grants access.

## Alternatives considered

Storing the label in `fields` was rejected: it is not a column the timeline can read. Always requiring the columns was rejected by ADR 0325.

## Consequences

Existing messages have no kind or name. The migration `messaging_actor_columns` adds the columns to the repository's stack.
