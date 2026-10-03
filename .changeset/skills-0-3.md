---
"better-supabase": patch
---

The Agent Skills cover 0.3. A new `better-supabase-auth` skill teaches sessions, typed claims, OAuth clients and agents behind a token (`session.actor`, `session.delegation` and the `scopes` guard option), `checkSession` before irreversible actions, what happens when claims change, and how to run next to PermDock. The `better-supabase` skill adds an upgrade workflow, cursor pagination, `Temporal` values, the CLI's `--json`, `--db-url-stdin` and exit codes, and `member_org_ids()` in tenant policies. The `better-supabase-api` skill adds `scopes`, cursor resources, the MCP `authorize`, `visible` and `allowedHosts` options, the kit's purge functions and the Postgres pool options. The `better-supabase-testing` skill adds delegated-token API tests, `Temporal` in tests and doctor in CI. Run `better-supabase skills install` to update installed skills.
