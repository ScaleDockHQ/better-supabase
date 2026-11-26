# 1253: Tenant scopes refuse by interrupt

- Status: accepted
- Date: 2026-11-26

## Context

A cached read that needs a tenant and a permission repeated the same ladder:
resolve the tenant record, check the session, check membership, check the
permission, and return `null` at each step. CentraKit has 453 of those `null`
checks, and the example app copies a `Loaded` and `settle` pair into 25 files.

## Decision

`createNext` gains three helpers and a `tenants` option.

- `bsb.auth(permission?, options?)` returns the `bsb.cached()` context with
  `user` and `can`.
- `bsb.tenant(ref, permission?, options?)` and `bsb.activeTenant(permission?,
  options?)` add `tenant` (the record the app's resolver returned) and
  `granted`. `bsb.tenant()` without arguments is still the root param getter.
- `createNext({ tenants: { by, resolve } })` names how a `TenantRef` is read:
  a string as `by` (default `id`), `{ id }`, or `{ <kind>: string }`.

A refusal throws the Next.js interrupt (ADR 1252): no session is
`unauthorized()`, an unknown tenant or a non-member is `notFound()`, a refused
permission is `forbidden()`. `.orNull()` and `.or(fallback)` on a read turn a
`not_found` error into `null` or the fallback and throw every other error, so
`db.x.get(id).orNull()` replaces `or-missing.ts`.

The helpers run `cached()` and `require()` together, so a refused caller never
gets rows that the page uses, and the permission check keeps its own
authorizer call. The tenant record type is `{ id: string }`; the resolver's
extra fields are present at runtime and typed as `TenantRecord`.

## Not in this decision

The plan's one-round-trip form, where the check starts without being awaited
and the returned `db` waits for it through `$wrapExecutor`, and `bsb.shared`,
which reads once per tenant under a restricted role, need a design for the
restricted role and a generic record type. They are deferred with their own
ADRs, and the helpers keep their signatures when they ship.

## Consequences

`TenantRef` is accepted by the new helpers. `cached`, `public`, `require`,
`sessionHandle` and `ActionOptions.tenant` still take a tenant id string.
