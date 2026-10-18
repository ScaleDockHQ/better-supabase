# 0039: Name PermDock as one optional auth choice on the Create page

- Status: accepted
- Date: 2026-10-18

## Context

Invariant 15 and ADR 0011 keep better-supabase free of any authorization
library: libraries plug in through `AuthorizationProvider`, and
`pnpm check:no-permdock` fails on PermDock's name or shapes across the
library, docs, marketing and examples. The Create page (`/create`) offers
the access models as raw values, and `provider` only says "set
`authorization` to its adapter". People who pick it have to find an adapter
and its setup on their own. PermDock 1.0 ships an adapter for
better-supabase 0.9 (`permdock/better-supabase`), so the page can show a
working setup for one library without the library depending on it.

## Decision

The Create page lists five auth choices: built-in roles, permission
tables, PermDock, your own provider and custom SQL. PermDock is marked
optional and maps to the library's `access: "provider"`; the preset code
never gains a PermDock value. The page keeps the choice in the URL as
`&authz=permdock`, and the Get code dialog adds the install and generate
commands and writes `authorization: authorizationProvider(...)` into the
config it shows.

Invariant 15 now reads: better-supabase never depends on an authorization
library; the Create page may name PermDock as one optional choice. The
check allows exactly the Create page's option module, its test, the Get
code dialog that renders the setup and the create e2e spec
(`scripts/check-no-permdock.ts`). The library, its docs elsewhere, the
skills and the examples still don't name it.

## Alternatives considered

- Keep only "Your own provider". It is correct but leaves the most common
  question (which library, and how) unanswered on the page that writes the
  config.
- Name PermDock in the library's preset or docs. That makes the library
  depend on one vendor's release cycle, which ADR 0011 rejected.
- List several libraries. Only PermDock has a better-supabase adapter
  today; others can join the list the same way once they ship one.

## Consequences

People who want typed permissions get a working config and commands from
`/create`, and people who roll their own keep the provider and custom SQL
choices. The allowlist grows by a few marketing files, so a PermDock
mention elsewhere still fails the check. A breaking change to
`authorizationProvider` or the PermDock CLI means updating
`apps/marketing/lib/create-options.ts`; revisit this if a second library
ships an adapter or PermDock stops shipping one.
