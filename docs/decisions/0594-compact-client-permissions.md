# 0594: Compact client permissions and a claims-free session

- Status: accepted
- Date: 2026-11-09

## Context

A session passed into a Client Component carried the whole JWT, including
memberships and permission lists. At 150 memberships the memberships claim is
about 14 KB (ADR 0523) and a full permission list for one tenant with 300 keys
is about 7 KB. The compact bootstrap form already existed on the wire
(`expandBootstrapPermissions`) but the client had no provider, and the
built-in permission tables still answered with `my_permissions` per tenant.

## Decision

`toSession(auth, { claims: false })` omits the JWT payload. `PermissionsProvider`
and `can` / `useCan` in `better-supabase/react` read either bootstrap form.
`better_supabase.bootstrap_permissions()` encodes the compact bitset in SQL for
the roles and catalog models. `claimFormat: "summary"` writes
`{ form, roles, tenants }` with a role index per tenant.

## Alternatives considered

- Sending the full claims and letting the client ignore them: the bytes still
  cross the boundary.
- One `my_permissions` call per tenant: the page pays a round trip per
  membership.

## Consequences

Client props stay small. A provider that writes its own bootstrap function is
unchanged. `summary` is opt-in because existing hooks read the array form.
