---
"better-supabase": minor
---

**Breaking:** 0.6 removes the deprecated aliases 0.5 kept for one minor. A support token whose `act` has `session_id` but no `kind` is refused as `invalid-chain`. The audit module (version 5) drops the read-only `better_supabase.audit_log` view; read `better_supabase.audit_events`. `maxUrlLength` is gone from `defineSupabase` and `postgrestExecutor` (use `urlLengthLimit`), `scopes` from the MCP server options (use `advertisedScopes`), and `createInbox` and the `Inbox*` types from `better-supabase/blocks/jobs` (use `createWebhookInbox` and `WebhookInbox*`). `better-supabase codemod 0.6` now renames the `Kit` and `Org` exports and `maxUrlLength`, and lists imports from the moved subpaths for review.
