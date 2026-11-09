# 0560: Keep `@ai-sdk/react` and the full Supabase browser client

- Status: accepted
- Date: 2026-11-08
- Amends: 0483

## Context

ADR 0483 moved the assistant's chat panel behind `AssistantChatLazy` and recorded
two ideas it did not build: a chat hook without `@ai-sdk/react`, and a browser
client without Realtime. This ADR measures both with the Turbopack analyzer
(`next experimental-analyze`) on the Next.js example and decides.

## Measured

- The chat panel's code is one async chunk of 209995 raw bytes (`ai`,
  `@ai-sdk/gateway`, `@ai-sdk/provider-utils`) plus a 129744 byte chunk for `zod`
  that only `ai` pulls in. Together they are 340 KB raw, and they load after
  the first paint of `/assistant`. The first load of `/assistant` is 1287968
  bytes against 1286438 for `/beta`, which has no chat: the hook costs the first
  load 1.5 KB.
- `@supabase/realtime-js` (32.4 KB) and `@supabase/phoenix` (25.2 KB) weigh 57.6
  KB in the analyzer, and `iceberg-js` (5.4 KB) comes with `storage-js`. They are
  in the first load of the 111 routes that render the live unread badge
  (`unread-badge.tsx`), out of 125 `[locale]` routes.

## Decision

Neither is built.

- **Chat hook.** `useAssistant` returns `UseChatHelpers`, so a replacement needs
  the stream reducer (`processUIMessageStream`, 25 chunk types in `ai` 7.0.159,
  several added in the last two minors) and the chat state machine
  (`AbstractChat`: submit, regenerate, resume, stop, tool approvals,
  `sendAutomaticallyWhen`, throttling), about 900 lines that must follow every
  change to the UI message stream. It removes nothing from any first load, and
  `tests/next-build` cannot see the saving. `better-supabase/ai-sdk/react` and
  `workflow-react` keep `@ai-sdk/react`, `ai` stays an optional peer (ADR 0010),
  and the chat panel stays lazy.
- **Browser client.** A client built from `auth-js`, `postgrest-js`, `storage-js`
  and `functions-js` would save at most 63 KB (about 4 percent of the smallest
  route) and would copy supabase-js's header, fetch and cookie wiring into the
  library. Every `(app)` route needs Realtime for the badge, so no route could
  use it. The upstream route, a Realtime client that `supabase-js` loads on the
  first `channel()` call, removes the cost without a fork.

## Alternatives considered

- Parity-test a copy of the reducer against `ai`'s own on every release. It bounds
  the drift but still ships 900 lines to save a deferred 340 KB.
- A `realtime: false` option. `supabase-js` constructs `RealtimeClient` in its
  constructor, so no option drops it (ADR 0483).

## Consequences

The first-load baselines do not move. Revisit the chat hook when the assistant
route gets a first-load budget of its own, or when `ai` ships a client entry that
leaves the gateway and `zod` out of the browser. Revisit the client when
`supabase-js` loads Realtime lazily, or when a route without the badge needs a
smaller entry.
