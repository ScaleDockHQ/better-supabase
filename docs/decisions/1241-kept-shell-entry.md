# 1241: Keep the page shell's one call as an entry per user

- Status: accepted
- Date: 2026-11-25

## Context

ADR 1233 reads the shell with one `shell_bootstrap` call held as one
`'use cache: private'` entry. A private entry lives in the browser only, so a
hard load, the second user of an organization (who has their own entry) and a
load after a restart all made the call again.

## Decision

`getShell()` in `src/features/shell/shell-queries.ts` still opens one private
entry, and inside it reads a `bsb.kept()` function named `shell`. The kept
function calls `public.shell_bootstrap` as the caller through the executor, so
RLS scopes the approvals count, and validates the payload with valibot. The
entry key holds the user, the active organization, the authorization version,
the schema hash and the library version (`bsb.kept` builds it). Its tags are
the user's session tags, the `bsb:<table>@<tenant>` tags of `memberships`,
`organizations` and `subscriptions`, and `APPROVALS_TAG`; it is fresh for 60
seconds and lives 300.

An organization switch changes the tenant in the key, so it reads another
entry. A role change calls `memberChanged`, which evicts the member's session
and expires every entry that carries their session tag. `tests/next/kept.test.ts`
covers both.

## Alternatives considered

- Call `bsb.bootstrap` inside the fill: it calls `cacheLife` and `applyEntry`,
  which belong to the enclosing private scope, not to a kept fill.
- Check `session_active()` in the fill: a banned user's entry ends with the
  session eviction or after its life, and the wrapper's check stays on every
  other bootstrap call.

## Consequences

The shell makes no database call on a warm kept entry. A user whose session
ends keeps a stale shell for up to 60 seconds unless the app evicts the
session. Revisit if the shell grows data that one user's write changes without
a table write through `db`.
