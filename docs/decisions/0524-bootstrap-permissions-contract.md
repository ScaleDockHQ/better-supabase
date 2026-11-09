# 0524: Return the caller's permissions from the bootstrap in a versioned, compact form

- Status: accepted
- Date: 2026-11-08
- Amends: 0115, 0129

## Context

A page that renders by permission (a button, a menu entry, a list column)
needs the caller's permissions. Today it asks the authorizer per check, reads
the `permissions` claim, or calls the library's own RPC. The bootstrap call
already returns the session check, the live authorization version and the
subject in one query (ADR 0115), so the permissions can ride along. The
wrapper must not name a library function, because the library is optional
(invariant 15), and the payload must stay small: a user in 150 tenants holding
300 keys each is 737 KB as lists of key names.

## Decision

A versioned, provider-neutral contract, `apiVersion: 1`, additive:

- `authorization.functions.bootstrapPermissions` is a template (`{tenant}`,
  `{scope}`) whose jsonb value is `BootstrapPermissionsWire`. The sessions
  bootstrap wrapper adds `'permissions', to_jsonb(<template>)` to its answer
  when the provider sets it, and never names a provider function itself.
  `permissions: false` on a bootstrap entry leaves it out. `{tenant}` is the
  call's tenant, or `null` for every tenant the caller belongs to.
- The full form lists keys per tenant. The compact form is a key index plus one
  bitset per tenant (and `platform`), base64 or base64url, bit `i` meaning
  `keys[i]` is held. `compactBootstrapPermissions` and
  `expandBootstrapPermissions` (`better-supabase/server`) convert between
  them; the types are in `better-supabase/contract`.
- `Bootstrap.permissions` is the expanded value, or `null` for a provider that
  returns none, another `apiVersion`, a malformed list, a bitset with a bit past
  the key list or a damaged encoding. The contract fails closed: nothing is
  guessed, and the page falls back to its authorizer.
- The permissions are data to render from. The decision stays with the
  authorizer; nothing in better-supabase turns a listed key into an allow.

## Measured

Bootstrap payload bytes for 150 tenants and 300 keys (a third of the keys
absent per tenant), `tests/core/bootstrap-permissions.test.ts`:

| Form    | Bytes   |
| ------- | ------- |
| Full    | 737,192 |
| Compact | 21,314  |

A provider whose tenants hold few distinct keys saves less; the compact form
never grows past the key list plus one bit per key and tenant.

## Alternatives considered

- Reading the `permissions` claim. Rejected: the token carries one tenant, is
  truncated past its budget, and its bytes land in the cookie (ADR 0523).
- A fixed `my_permissions` RPC. Rejected: it names a library function in the
  wrapper.
- Run-length or delta encodings. Rejected: bitsets decode with a loop and no
  library, which any provider can write in SQL.

## Consequences

Closes scale item 9.5 on the better-supabase side: a provider's compact snapshot
plugs in by setting the template. `upgrade` rewrites the `sessions` module file
for an app whose provider sets it, `db diff` then updates the wrappers, and no
data migration is needed. A provider that returns no value changes nothing.
The key index and bit order are part of `apiVersion: 1`; changing either needs
a new version.

## Server size

The shared server chunk grows with this track's runtime code (the permissions
reader, the JWKS purge and the claim readers): per-route server baselines rose
by 1.6 to 2.6 KB raw (0.1 percent) and by up to 0.84 KB gzip, for example
`/[locale]/(app)/customers/page` 1,603 B raw and 648 B gzip more. The client
first-load baselines did not move. The baselines were raised by hand in the
same commit, as the update script never raises them.
