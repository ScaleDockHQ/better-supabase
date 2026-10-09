---
"better-supabase": minor
---

Errors map to typed messages and result libraries, plugins behave the same whoever wrote them, and each definition keeps its own state.

- `createErrorMessages(messages)` needs a message for every `DbError` kind. `toBetterResult` returns better-result's own `Result<T, E>` when that is the expected type, and `defineBetterResultErrors` maps kinds to `TaggedError` classes. `P0002` maps to `not_found`.
- Plugins get `enforce: "first"`, a mutation `intent`, `scopes`, and a `context` hook per `connect()`, so two definitions in one process no longer share a tenant. Hooks receive the caller's `signal`, and `db.$withoutPlugins({ keep })` keeps named plugins.
- `defineSupabase(schema, { temporal })` takes the `Temporal` namespace without patching `globalThis`, and `diagnostics: true` logs a record without tokens or row values for every query.
- **Breaking:** `DbError` gains the kinds `quota_exceeded` (429), `max_affected` (400) and `unsupported` (501). An exhaustive `switch` over `DbError["kind"]` needs the new cases.
