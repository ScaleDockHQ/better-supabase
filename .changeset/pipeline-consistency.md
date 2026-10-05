---
"better-supabase": minor
---

Make the plugin pipeline behave the same on every path.

- `transformQuery` and `beforeMutation` receive the caller's `signal` in their args.
- A hook that throws something other than a `DbException` now fails the call with an `unexpected` error that names the table and, in `details`, the plugin and hook, and the `error` event fires. Before, the error had no table and no event fired.
- `db.$withoutPlugins({ keep: ['otel'] })` keeps the named plugins; an unknown name throws.
- `new BetterSupabase(schema, plugins)` checks `apiVersion` and duplicate names like `use()` does.
