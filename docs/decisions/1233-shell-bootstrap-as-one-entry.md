# 1233: Read the page shell with one bootstrap call and one private entry

- Status: accepted
- Date: 2026-11-25

## Context

Every hard load of the Next.js example made three shell calls: the
organizations for the switcher, the profile for the user menu and the pending
approvals for the navigation badge. Each ran in its own `'use cache: private'`
function. The plan target is one call for the shell, so a page costs its own
reads and nothing else.

## Decision

`public.shell_bootstrap(args jsonb)` returns the organizations, the profile,
the pending approvals count and the compact permissions (ADR 0524) in one
select. The sessions block's `bootstrap.shell` option wraps it as
`api.bootstrap_shell`, with the session check and the authorization version.
`features/shell/shell-queries.ts` exposes `getShell()`, one private cache
entry with `cacheLife({ stale: 30, revalidate: 60, expire: 300 })` and the
approvals tag. `getMyOrganizations`, `getMyProfile` and the badge read it.

`bsb.bootstrap` dedupes per request through React `cache()`, but that cache
does not span separate `'use cache: private'` scopes: the first attempt, where
each reader called `bootShell()`, still made three calls (measured: calls
unchanged, tables 4 to 2). One shared entry is what removes them.

## Alternatives considered

- Each reader calls `bootShell()`: three calls, as measured.
- Pass the payload down as props from the layout: removes the cache entry but
  touches every consumer of the three readers.
- Keep the organizations and the profile on their longer life and only the
  badge short: needs two calls again.

## Consequences

A hard load makes two fewer calls (`/finance/invoices` and `/settings/roles`
4 to 2, `/customers` 7 to 5, `/` 5 to 3, `/customers/[id]` 13 to 11). The
organizations and the profile now share the 30 second stale window of the
badge; a write to their tables still tags the entry out at once. Revisit when
a kept shell entry on a durable store replaces the private entry.
