# 0019: Read-only actors are refused inside security definer writes

- Status: accepted
- Date: 2026-10-13

## Context

Support sessions default to `read_only`. Audit columns and the actor label
read the `act` claim, but a `security definer` function runs as its owner
and bypasses row level security. A restrictive policy on the table never
sees the write, so a read-only support or impersonation session can still
change data through those functions.

## Decision

`better_supabase.actor_may_write()` reads `request.jwt.claims` and returns
false when `act.kind` is `support` or `impersonation`, or when `act` has
`session_id` and no `kind`, unless `act.read_only` is `false`. A token
without `act` may write.

`applyActorWriteGuards` in `src/sql/actor-guard.ts` inserts that check at
the start of every `security definer` function that writes and is granted
to `authenticated` or `anon`, and adds it to `using` and `with check` of
write policies for `authenticated`. `start_support_session`,
`end_support_session` and `expire_support_sessions` are the exception, so
a session can still be opened and closed.

`authorization.functions.actorMayWrite` replaces the built-in call. When
the template is set, the generated SQL calls it and not both. Doctor BS413
warns when support sessions are on, the access model is `provider`, and
the template is missing.

## Alternatives considered

- **Rely on restrictive policies.** Definer functions never hit them.
- **Check only in the TypeScript clients.** A direct RPC skips the client.

## Consequences

Writes that succeeded during a read-only session in 0.8.0 now fail with
`ACTOR_READ_ONLY` (`42501`). A provider that wants its own helper sets
`actorMayWrite`. The guard is applied when the module SQL is rendered, so
a new write function is covered without a per-function edit, and the
allowlist is the only way out.
