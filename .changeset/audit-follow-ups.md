---
"better-supabase": patch
---

CLI fixes. `doctor --claims` without `--explain` exits with code 2 instead of being ignored. A failed database connection suggests `supabase start` only when a local host refused or dropped the connection, not for a remote host or a rejected password. `openapi emit --check`, `seed --check`, `skills install --check`, `scaffold api --check` and `spec check` print the diff of each stale file. `codemod --help` lists the 0.9 codemod.

`bs.resource` in `better-supabase/hono` matches paths with the same rules as `resourceRouter`: a malformed id returns a 400 `invalid_input` problem, and an unknown path under the resource returns a 404 problem instead of Hono's plain-text 404.
