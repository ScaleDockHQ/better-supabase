---
"better-supabase": patch
---

Fix four places where one part of an app could widen what another allowed:

- A job enqueued in a read-only support session ran with write access. Jobs now record the session's `act` claim, and `bs.forContext(job.context)` keeps it, so the job runs read-only as the same support session. `forContext` refuses a context whose `act` claim is not a valid chain.
- `createMcpAuth` instances shared the set of auth states they had verified, so a second instance accepted a caller without its own `allow`, `aal` and `requiredScopes` checks. Each instance now trusts only what it verified, and `contextOf` checks a bare token against those options too.
- `bs.middleware()` in `better-supabase/hono` no longer reuses the verification `withSupabase` stored in `c.var.supabaseContext`. That reuse added the token to a cache shared by every server with the same keys in the process, so a value another middleware set could vouch for a token those servers would reject. The token is verified once per process, then cached until it expires.
- `better-supabase gen --watch` retried a failed run only after the next schema change. It now retries every interval and prints the same error once. `--interval` must be a positive number of milliseconds.

`gen` also refuses a generator file outside the project root or on a path that `gen` or another generator writes, and names the generator when `generate` throws.
