# 0011: Define a neutral authorization provider and let libraries ship adapters

- Status: accepted
- Date: 2026-10-09

## Context

Until 0.5 the access contract had settings for one authorization library:
its catalog file, its SQL helper names and its key prefix. An app on another
library, or on its own permission tables, had to fake that library's shapes,
and every release of the library could break better-supabase. Invariant 1
keeps the core free of runtime dependencies, and the SQL modules need
permission answers inside RLS policies, so the library has to be reached
through SQL, not through a TypeScript import.

## Decision

better-supabase defines `AuthorizationProvider` in
`src/config/authorization.ts`, versioned with `apiVersion: 1` (invariant
10). A provider names its scopes and the tenant scope, gives SQL templates
for `can()` and `tenant_ids_with()` (`idsWith`, `isPlatform` and the
optional `For`, `memberIds` and `canAssign` variants), and may describe its
permission keys, memberships, role sources, suspension rows and the access
token hook. The app sets it in the `authorization` key of
`better-supabase.config.ts`, and the `access` module compiles the templates
into its functions. Doctor checks the provider's `requires` and
`decidingColumns`.

Authorization libraries ship their own adapter that returns an
`AuthorizationProvider`. better-supabase never depends on one and never
names one: invariant 15, enforced by `pnpm check:no-permdock`, with the
provider page and the 0.5 to 0.6 guide as the only exceptions.

## Alternatives considered

- Keep the library-specific settings and add more libraries next to them.
  Each library would pin better-supabase to its release cycle and grow the
  config with options most apps never use.
- An optional peer per library, loaded lazily. It still names the library
  in the package, and the permission check has to run in SQL anyway.
- Only fixed roles and the app's own role tables. Apps with a permission
  library would duplicate its data to fit.

## Consequences

The access contract works the same over fixed roles, the app's own tables,
existing SQL functions or any library with an adapter. Libraries own their
adapter and can release it on their own schedule. A change to the provider's
shape needs `apiVersion: 2` and a conformance case, so additions should stay
optional fields. Apps upgrading from 0.5 move the old settings to their
library's adapter, as the 0.5 to 0.6 guide describes.
