# 0010: Keep AI blocks SDK-neutral and bridge each SDK in an adapter subpath

- Status: accepted
- Date: 2026-10-08

## Context

The next releases add AI chat, durable workflows, agents, connectors and
chat-platform bots. Each has more than one SDK an app might use: the AI SDK,
TanStack AI or the OpenAI Responses API for chat; the Workflow SDK or
Temporal for durable runs; the Chat SDK for Slack and Teams; Vercel Connect,
Nango or a cloud secret manager for third-party tokens. The tables, RLS,
lifecycle and permissions are the same whichever SDK runs on top. Invariant 1
keeps the core free of runtime dependencies, and invariant 6 keeps runtime
entries on WinterTC APIs.

## Decision

The code is split into three layers.

1. **Neutral blocks** (`better-supabase/blocks/*`, `better-supabase/streams`,
   `better-supabase/credentials`) own the SQL modules, RLS, functions,
   topics, lifecycle and a typed server API. They import no AI, workflow or
   chat SDK. They follow the "A block" row in `AGENTS.md`.
2. **Engine storage modules** are SQL modules an engine needs to persist
   its own state (a Workflow SDK World, for example). They register their
   runs in an engine-neutral run registry the blocks read, so a block never
   depends on the engine's tables.
3. **SDK adapters** (`better-supabase/ai-sdk/*`, `workflow-sdk/*`,
   `chat-sdk/*`, `vercel-connect`, `eve`) convert the SDK's types to the
   blocks' types and wire the SDK's hooks to the block functions. An adapter
   never owns a table or ships SQL; when it needs storage, a block or an
   engine module provides it. Each SDK is an optional peer loaded lazily, or
   typed structurally (invariant 12).

Messages are stored in a canonical format: `ai_messages.parts` holds the
part list in `src/blocks/ai-chat/message.ts` (`text`, `reasoning`, `file`,
`tool-call`, `tool-result`, `tool-approval`, `source`, `data`, `step`),
published as `schemas/ai-message-v1.json` and pinned as `SPEC_PINS.aiMessage`.
A `native` column may keep the SDK's own message for lossless replay. An
adapter maps its SDK's parts one to one and turns a part with no counterpart
into a `data` part, and its converter tests fail on an unknown part.

Resumable output goes through the `StreamStore` interface in
`better-supabase/streams` (Postgres through the `streams` SQL module, or
Redis), so a chat, a workflow and an agent share one resume and cancel path.

No column holds a third-party token. A table that needs one stores a
`credential_ref jsonb` naming it, and a `CredentialProvider` (apiVersion 1)
resolves the ref. `vaultCredentials()` over the `credentials` SQL module
(Supabase Vault, service role only) is the default, and
`better-supabase/vercel-connect` is the first adapter. The provider is a
`createServer` option, exposed as `ctx.credentials`, because it needs a
transport at runtime and `better-supabase.config.ts` is read by the CLI.

## Alternatives considered

Building the blocks on the AI SDK directly would be less code for the first
release, but ties every table and hook to one SDK's message shape and makes
a second SDK a migration. Storing only the SDK's native message avoids the
converter but makes queries, search and memory depend on that shape.
Encrypted token columns on each table would repeat key management per block
and make revoking a connection a schema change.

## Consequences

A second SDK for chat or workflows is an adapter subpath, not new tables.
Every adapter carries a converter and its tests, and a new SDK part type
needs a canonical counterpart or the `data` fallback. Changing the canonical
format is a new schema version and a new pin. Revisit if one SDK becomes the
only one apps use and the converter costs more than it saves.
