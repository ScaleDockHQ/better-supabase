---
"better-supabase": minor
---

Jobs and workflow runs that an OAuth or MCP client queues keep the client's limits: the envelope records the token's `client_id`, `scope`, `authorization_details` and full RFC 8693 `act` chain, and `bs.forContext` runs with them instead of the user's full rights. The new SQL helper `better_supabase.token_scope_allows(scope)` in the `actor` module checks a delegated token's scope in policies.

`enqueue` fails with `forbidden` for a context with an invalid `act` chain or malformed delegation claims, and `forContext` refuses such a stored context. `ServerOptions.claimsFor` can no longer set `act`, `client_id`, `scope` or `authorization_details`. A job's `delay` must be a whole number of seconds, else `enqueue` fails with `validation`.

Jobs and workflows take an opaque `ticket`: the `ticket` enqueue option, `startFor(ctx, workflow, args, { ticket })`, `workflowContext(ctx, { ticket })` and `startOnEvent({ ticket })`. Runs carry it as the `bs.ticket` attribute, and `forContext` resolves it through `ForContextOptions.ticket` or the provider's `tickets.subject` hook, failing with `forbidden` when nothing resolves it. `startOnEvent`'s `args` now gets the event's context as a second argument.

`better-supabase/workflow-sdk` exports `approvalWaiter`: `wait(token, { expiresAt })` pauses a run until `wake(token, payload)` or the RFC 3339 deadline.
