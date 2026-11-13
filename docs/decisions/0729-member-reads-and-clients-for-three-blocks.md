# 0729: Member reads and clients for three blocks

- Status: accepted
- Date: 2026-11-12

## Context

The example app's follow-up pass (audit program, lane E) found three blocks
that only the service role could use from TypeScript, or not at all:
`field-encryption` had no member-callable read, `vercel-marketplace` had no
tenant-scoped read and no env contract, and `impersonation` had no client, so
the example called `db.$client.schema("api").rpc(...)` by hand. The session
provider also hard-coded the `api` schema for `caller_authz_version()`.

## Decision

`field-encryption` gets `field_key_status()` (member and service role, returns
owners and key presence, no key material) and a `createFieldEncryption` client
with `keyStatus()`. `vercel-marketplace` gets `marketplace_installation_for` and
`marketplace_resources_for` for members of the tenant, plus `installationFor`
and `resourcesFor`, and lists its two env keys in the manifest. `impersonation`
gets `createImpersonation` over its existing functions. `SessionProvider` and
`realtimeVersionSource` take a `schema` option that defaults to `api`. `doctor`
reads the `.gitignore` files up to the repository root, and `gen --check`
classifies stale files as subject, search or other.

The new functions are `security definer`, because they read Vault names and
tables that members cannot select. The practices baseline for definer functions
rises by 4 for `field-encryption` and 12 for `vercel-marketplace`.

## Alternatives considered

Granting members `select` on the marketplace tables would expose the Vault
handle of the access token. Returning a set from `field_key_status` would break
`sqlTransport`, which reads one value per call, so it returns one jsonb array.

## Consequences

Apps drop raw `rpc` calls for these blocks. A rotate action and a count of
encrypted columns for `field-encryption` stay open, as do the `period_start`
and `target_user_id` renames (EX-1613) and the `t(...)` extractor warning
(EX-1602); both need their own changes.
