---
"better-supabase": minor
---

AsyncAPI channels now come from the same `defineTopic` definitions that `sql sync` turns into Realtime policies. Pass `topicsFrom(module)` (from `better-supabase/asyncapi`) to `defineApi({ topics })`. Each channel gets its broadcast events, its presence schema and an `x-better-supabase-realtime-status` of `beta` for private topics (Realtime Authorization is still in public beta) or `ga` for public ones. A topic gets a send operation only when it sets `clientSend: true`; before, every topic got one. `defineTopic` takes the new `presenceSchema`, `clientSend` and `status` options, and a topic exposes `events`, `clientSend`, `permission` and `status`.

`better-supabase spec` loads the `realtime.policies.from` modules with the loader `sql sync` uses. It warns `asyncapi-topic-undocumented` for each topic the AsyncAPI document leaves out, and `--watch` renders again when a topic module changes.

The new `dataApi` option documents the Supabase Data API next to your routes: `/rest/v1/<table>` operations and `/rest/v1/rpc/<function>` calls, with database column names, the API key and JWT schemes, the PostgREST error body and their own `servers` from `supabaseUrl`. Operations take an optional `servers` list, which the OpenAPI formats render. New diagnostics: `data-api-server-missing`, `data-api-table-unknown` and `data-api-function-unknown`.
