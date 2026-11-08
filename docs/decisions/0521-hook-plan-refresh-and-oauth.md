# 0521: Plan the access token hook: reuse a current refresh, slim OAuth tokens

- Status: accepted
- Date: 2026-11-08
- Amends: 0033, 0116

## Context

Supabase Auth runs the custom access token hook on every sign-in and refresh,
with a 2 second limit. The app's hook read the user's memberships and
permission keys each time, although a refresh whose `authz_ver` is still the
user's current version would write the same claims again, and an OAuth client
token (the MCP server issues those, with a `client_id` claim) never uses them.

## Decision

The sessions module renders `better_supabase.hook_plan(event)` when
`blocks.sessions.options.hook` is set. It returns `slim`, `reuse` or `full`:

- `slim` for a token with a non-empty `client_id`, when `oauth` is `'slim'`
  (default `'full'`).
- `reuse` for a `token_refresh` event whose claims carry a numeric `authz_ver`
  equal to the user's current version (own table or `authorization.versions`),
  a `memberships` array and no truncation flag (`truncatedClaim`, default
  `permissions_truncated`, and `team_ids_truncated`). `refresh` is `'reuse'` by
  default and needs a version source; `'full'` turns it off.
- `full` otherwise.

The app's hook calls it first and returns the event unchanged for `slim` and
`reuse`. Supabase Auth builds refresh claims itself, so `reuse` applies only
where the event carries the previous token's `authz_ver`; any doubt reads
again. Suspension and the active tenant claim are the app hook's to re-check
on a refresh it cares about, as the hook may do before calling the plan. The
fixture hook (`rbac.custom_access_token_hook`) uses the plan.

The function is a stable `security definer` plpgsql function granted to
`supabase_auth_admin` and `service_role`. It reads only the version and the
event, so it needs no other module. `tests/sql/modules/sessions.test.ts` and
`supabase/tests/database/hook_plan.test.sql` cover it.

## Alternatives considered

- Rendering the whole hook. Rejected: the claims depend on which modules and
  provider an app uses, so a generated hook would name functions that may not
  exist. A plan function keeps the module free of other modules.
- Reusing without comparing versions. Rejected: a role change would not reach
  the token until it expired.

## Consequences

Membership reads per fast refresh: 1 before, 0 after (pgTAP counts
`membership_claims` calls with `pg_stat_get_xact_function_calls`). An app opts
in with the option and a one-line change in its hook; `upgrade` rewrites the
sessions module file and a migration adds `hook_plan`. No data migration. A
provider that ships its own hook ignores the function.
