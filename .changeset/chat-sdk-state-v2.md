---
"better-supabase": minor
---

`chat-sdk-state` is now version 2: TTLs are `bigint` milliseconds, list trimming takes an advisory lock, and `createSupabaseState().connect()` fails with a clear error when the module is missing. Re-run `better-supabase add chat-sdk-state` and apply the migration; the upgrade drops the version 1 `int4` functions.

The scheduler stores its queue under `better-supabase:scheduled` instead of `chat:scheduled`. A value under the old key is read once and moved.

| Old              | New                         |
| ---------------- | --------------------------- |
| `chat:scheduled` | `better-supabase:scheduled` |

Also new in `better-supabase/chat-sdk`: the `ChatInboundStore` port (`inboxStore`, `webhook({ sink })` for the queue block's webhook inbox), `capabilitiesOf` (needs the optional peer `@chat-adapter/catalog`), and `InboxAdapter` support for actions, reactions, stop actions, file upload and `ai_generated` metadata.
