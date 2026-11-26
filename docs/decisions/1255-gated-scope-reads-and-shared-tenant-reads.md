# 1255: Gated scope reads and shared tenant reads

- Status: accepted
- Date: 2026-11-26

## Context

ADR 1253 runs `cached()` and `require()` together and returns the scope after
the permission check settles. A cold call still waits for the slower of the
two before the first read can start, and a read that is the same for every
member of a tenant is cached once per user.

## Decision

`ScopeCallOptions.gate: true` starts the permission check without awaiting it
and returns the scope at once. `db` is wrapped through `$wrapExecutor`: every
read, `rpc` and `$many` batch starts under RLS and settles only after the check.
A refusal settles the read with a `forbidden`, `not_found` or `unauthorized`
error Result. A repository never throws for a database error (invariant 4), so
the gate returns the refusal as data and the page chooses what to do with it.
A caller without a user session is still refused before the scope returns,
because `user` is typed as a user.

`bsb.shared(ref, permission, read)` checks membership and `permission` outside
any cache, with the same interrupts as `bsb.tenant()`, then returns
`read(tenant)`. The app writes `read` as a `"use cache"` function of the
tenant, so the entry is shared by every member and a refused caller never
reaches it.

## Not in this decision

The plan named a restricted database role for the shared read. That role needs
SQL in the app's schema, a migration, and a review of which tables it may see,
so the library does not create it. The shared read runs under whichever client
the app's `read` uses (`bsb.admin()` with an explicit tenant filter, or a role
the app defines). The docs say so.

## Consequences

`gate` is opt in: the default scope still returns only after the check. Do not
treat `can` or `granted` as proof before the first gated read settles.
