---
"better-supabase": minor
---

Make the plugin contract work the same for third-party plugins as for the built-in ones. `enforce: 'first'` is a new hook level for plugins that check the query as written; `rules()` uses it, and hook order no longer depends on a plugin's name. Mutation ops carry an optional `intent` that the rewriting plugin sets (`softDelete()` sets `softDelete`), so core no longer guesses that any delete turned into an update is a soft delete. A new `scopes` field lists the table flags a plugin's `transformQuery` filters, and `defineReadSet` warns from it instead of from the tenant and soft-delete flags. The `tenant()` plugin, storage, jobs and `rules()` resolve the tenant through one function, and `testPlugin` now checks `enforce`, installs the plugin next to the first-party plugins in both orders, and fails a `repository` hook that replaces a base method.
