# 0114: Give authorization libraries a typed, additive contract

- Status: accepted
- Date: 2026-10-27

## Context

An authorization library plugs into better-supabase through the slots of ADR
0011 and ADR 0096: a provider object, an authorizer, hooks and a version
cache, each at `apiVersion: 1`. Writing an adapter against them still meant
copying claim names, reading table names from the config by hand, guessing
whether a request was a read or a write, and casting the version cache back
to the library's own type. The `permissions` claim listed keys the SQL
functions can't decide, so a claim-based check granted more than RLS would,
and nothing stopped two hooks from writing that claim. An
`approval-required` answer had no way back in.

## Decision

Everything is additive under `apiVersion: 1`, and every new type is pinned in
`tests/core/authorization-library-contract.test-d.ts`.

- `better-supabase/claims` exports the claim names, `permissionsOf`,
  `isTruncated` and the session guards, with no server code.
  `better-supabase/contract` re-exports every slot and request type, types
  only, with `ContractApiVersion`.
- The `permissions` claim carries `sqlComplete` keys only. A provider whose
  hook owns the claim gets no `permissions` lines in the hook template, and
  `tokenHook.truncatedClaim` names its marker. Doctor BS407 reports a second
  writer and BS419 warns when `permissionsAuthorizer` meets unmarked keys.
- Each request carries `context.intent`, `operation`, `requestId` and
  `approval`, and `resource.source` (`loaded` or `input`) plus
  `resource.change` (`current`, `next`) for writes. `resource.properties`
  keeps its meaning.
- `versions` is generic through `createServer`, `createNext`, `createHono`,
  `createEdge` and `createMcp`, so `AuthorizerRuntime<V>` is the library's
  cache. Edge and MCP decisions go through the server's bound authorizer.
- `ServerOptions.approval.header` and MCP `_meta.approval` carry an approval
  id into `context.approval`; MCP keeps approval-required tools listed.
- `blockTables(config)` in `better-supabase/sql` resolves the memberships,
  membership roles and tenant tables with their renames.
- `better-supabase/testing` adds `authorizationRequest` and `sessionSnapshot`,
  and the kits check write requests, the truncated marker and the
  `sqlComplete` rule. Two fixture providers, one owning `permissions` and one
  leaving it to better-supabase, pass both kits.
- Each codemod publishes its renames as `codemods/<version>.json`, generated
  by `pnpm gen:codemods` and checked by a drift test.

## Alternatives considered

- A new `apiVersion: 2`: every field is optional or a new export, so existing
  adapters keep compiling, and a version bump would force them all to move.
- Replacing `resource.properties` with a typed `before`/`after`: it would
  break adapters that read `properties`. `change` sits next to it instead.
- Shipping UI gates (route guards, `<Can>` components) in better-supabase:
  they depend on how a library models permissions, so they belong in the
  library's client package on top of `better-supabase/claims`.

## Consequences

An adapter imports types from one entry, reads claim and table names from
better-supabase, and decides writes with the stored row and the new values
side by side. The claim no longer grants a key RLS would refuse. The
contract test grows with every new field, and a library that wants a field
removed has to wait for `apiVersion: 2`.
