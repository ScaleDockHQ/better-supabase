---
"better-supabase": minor
---

New sessions option `hook` renders `better_supabase.hook_plan(event)` for the app's access token hook. It returns `slim` for a token with a `client_id` (the MCP OAuth server's tokens, with `oauth: 'slim'`), `reuse` for a refresh whose `authz_ver` is still the user's current version, and `full` otherwise, so a fast refresh makes 0 membership reads instead of 1 and an OAuth client token reads nothing. `refresh: 'reuse'` needs `authzVersions` or a provider with `versions`. `better-supabase upgrade` rewrites the sessions module only for an app that sets `hook`, and `db diff` then adds the function; no data migration is needed. Call the plan first in your hook and return the event for `slim` and `reuse`.
