# 0104: RLS that is safe by default

- Status: accepted
- Date: 2026-10-25

## Context

The audit found these gaps: app-table writes skip `actor_may_write()` (fixed in 0.20.x); the
tenant scope is `to authenticated`, so a `to anon` or `to public` policy reads across tenants;
the restrictive policy is `for all`, so a block's select branch satisfies an app's update or
delete; nothing revokes `PUBLIC` or sets default privileges; `none` scope admits anonymous users.

## Decision

- The restrictive tenant scope is one policy per command, `to public`, so it narrows anon and
  every other role. Branches stay per command (ADR 0099 amended).
- Every schema the app exposes gets `alter default privileges ... revoke all on tables, functions,
  sequences from public, anon, authenticated`, and `revokeTable` also revokes from `PUBLIC`.
- `rls-guard` is on by default and also catches `disable row level security`.
- App tables exclude anonymous users (`is_anonymous` claim) unless the table asks for them, and
  `none` scope no longer admits `anon`.
- Authorization templates are checked at config load and in `gen` with a tokenizer.
- The service-role check reads the role PostgREST set, not the `request.jwt.claims` setting.

## Alternatives considered

- Leave defaults and rely on doctor: doctor warns after the fact, and a missed warning is a leak.

## Consequences

Breaking for apps that relied on the open defaults. Each hardening step has a changeset and a
migration note.

## Status note

- Done: the tenant scope is one restrictive policy per command (`bsb_tenant_scope_select`,
  `_insert`, `_update`, `_delete`), `to public`; a block's anon or public policy keeps its
  condition inside the matching command's scope policy.
- Amended (0.45): `to public` also covers `supabase_auth_admin`, which runs a `security invoker`
  custom access token hook without `auth.uid()`, so the hook saw no rows. `tenantScope.exemptRoles`
  (under `database.sql` or per block) adds a `current_user = any (...)` branch to each scope policy
  and grants the exempt roles `execute` on the functions the scope calls, because Postgres checks
  that privilege before `or` skips a branch. The exemption lifts only the restrictive scope: the
  role still needs its own grant and permissive policy. Doctor reports the hook as BS421.
- Done: `rls-guard` catches `alter table` (0.23.x) and `init` writes it into a new config; the `none`
  scope refuses anonymous sign-ins.
- Not done, by decision: the service-role check keeps reading the JWT claim. Block functions raise a
  caller to the service role on purpose by setting `request.jwt.claims` inside `security definer`
  code (`context.ts`, `orders-shared.ts`, `mail-sync-functions.ts`, `app-table-seal.ts`), so a check
  that reads the `role` setting first rejects the library's own calls (the integration suite showed
  it). A request can't set that claim: PostgREST sets it per request and `set_config` is not exposed.
- Done: every `revoke all` on a table or sequence a block creates also revokes from `PUBLIC`, and a
  block instance schema revokes default privileges for later objects (`revokeDefaults`).
- Not done, by decision: `alter default privileges ... revoke all` in `public` and in
  `better_supabase`. Hosted projects grant new `public` tables to the API roles through default
  privileges, and revoking them would silently break the user's own tables; the `grants` block and
  `expose` are the opt-in. In `better_supabase` no default grant exists to revoke, and the
  statement made pg-delta's declarative shadow load stuck on the attachments and catalog files.
