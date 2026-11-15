# 1033: Seed the entity pages after every local reset

- Status: accepted
- Date: 2026-11-15

## Context

ADR 1032 moved the demo rows of the periods, commissions, referrals and
invitations pages out of the SQL seeds and into the generated `*.seed.ts` files.
Those files are inserted by `pnpm db:seed:pages`, so a fresh `pnpm supabase:reset`
left the four pages empty until someone ran that command.

## Decision

`pnpm supabase:reset` runs `scripts/supabase-reset.ts`: `supabase db reset` with
the same arguments, then `scripts/seed-entity-pages.ts`. `worktree-setup --db` and
`pnpm dev:example` run the same seed script after the stack is up, and
`dev:example` goes on when it fails. A reset that names `--sql-paths` (the
library reset, `pnpm supabase:reset:library`) skips the page seeds, because the
pgTAP suite runs on the library rows only. CI is unchanged: the database
workflow resets with the library seed, and no Playwright or Runtime job seeds
the example.

The seed script inserts only rows an identity column does not already match, so
a second run adds nothing and `/invite/seed-invitation-acme` keeps working: its
row stays in `supabase/seed.sql`.

## Consequences

A reset takes a few seconds longer. This is repo tooling with no user-visible
change, so it has no changeset.
