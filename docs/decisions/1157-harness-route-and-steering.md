# 1157: Run HarnessAgent turns with sealed resume state

- Status: accepted
- Date: 2026-11-21

## Context

`@ai-sdk/harness` 1.0.190 exports `HarnessAgent` with `createSession({ resumeFrom })`,
`session.detach()` and `session.experimental_steerTurn`. The `ai-chat` block
already has `AiHarnessSessions` with a `resume_state` jsonb column and a lock.
A resume state can hold provider credentials.

The queue block has static named queues and no way to claim a message by
payload, and pgmq's `conditional` read is not exposed, so a per-chat steering
queue cannot be built on it.

## Decision

`harnessRoute` (`src/ai-sdk/agents/harness.ts`) locks the chat, resumes,
streams, detaches and stores the state sealed by `harnessStateCipher`
(AES-GCM, AAD `chatId\nharnessId`, key ids for rotation) in the existing
column, so no SQL changes. Steering is saved as a chat message and a poll loop
passes new messages to `experimental_steerTurn`. `@ai-sdk/harness` becomes an
optional peer (>=1.0.190 <2) listed in `tests/optional-peers.test.ts`.

## Alternatives considered

A steering table: rejected, it duplicates chat messages and needs the full
SQL module checklist. The queue block: rejected, see Context.

## Consequences

A steering message waits up to `steerPollMs`. Revisit if the queue block can
claim by payload.
