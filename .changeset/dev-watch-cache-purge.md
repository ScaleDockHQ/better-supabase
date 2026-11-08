---
"better-supabase": minor
---

`better-supabase dev` replaces `gen --watch`: it listens for file events on the config, `supabase/schemas` and the task inputs, prints `Ready` once on stderr, and reruns only the tasks a change affects. `gen --watch` and `gen --interval` exit 2 with `flag_renamed`. `better-supabase cache purge [--dry-run]` deletes the CLI cache. A warm `upgrade` on a large project drops from about 1.4 s to 0.4 s because the adoption scan is memoized in `node_modules/.cache/better-supabase/memo`, and `upgrade` no longer renders the modules twice to plan renames. `upgrade --json` reports `data.cache.rendered`, the module files a fresh render produced.

| Old                          | New                  |
| ---------------------------- | -------------------- |
| `gen --watch --interval 500` | `dev --interval 500` |
