# 1231: Carry the permission claim as a bitset

- Status: accepted
- Date: 2026-11-24

## Context

The `permissions` claim listed every key the caller holds. With 413 keys in the
catalog an admin's access token was 4,035 bytes and its cookie 5,567 bytes in 2
chunks. A member's list did not fit the 2,048 byte budget, so the hook set
`permissions_truncated` and the app read `my_permissions()` on every gated page.

## Decision

The roles and catalog models generate `better_supabase.permission_claims_bitset`.
The claim holds `{ h, b }` per tenant: an 8 character md5 prefix of the sorted
catalog keys and a base64url bitset over that order. The example hook uses it for
every role and drops the truncation marker. `permissionCatalog` in
`better-supabase/claims` builds the same order and hash in TypeScript (a small
md5, because runtime entries import no Node built-ins), and `expandPermissionBitset`
returns `undefined` for a hash or length it does not know. Readers then fall back
to `my_permissions()`, so a catalog drift never turns into a wrong answer.
`gen` writes `permissionKeys` so an app has the catalog list without a copy.

## Alternatives considered

- Fold keys into wildcards. It saved bytes for owners only and left the member
  truncated.
- Put the hash on the user instead of the claim. The reader then needs a second
  lookup to detect drift.

## Consequences

The catalog the app reads must match the table row for row. The example lists 7
legacy keys by hand for that reason. Existing key-list claims keep working.
