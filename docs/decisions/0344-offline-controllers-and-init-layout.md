# 0344: Pause block controllers offline and write the Next.js layout from init

- Status: accepted
- Date: 2026-11-07
- Amends: 0030, 0310, 0316

## Context

`experimental.useOffline` retries a navigation or a Server Action once the
network returns, but a block query in a Client Component showed an error, and a
block write failed. `init` for Next.js wrote two files, so a new app started
outside the layout the architecture check holds the example to.

## Decision

The controllers of ADR 0030 stay framework-agnostic: `createBlockQuery` and
`createBlockMutation` take an `offline` option and expose `setOffline`. A paused
read keeps the last data and holds one run for `setOffline(false)`; a write
queues in one slot, shares its promise across calls and sends on reconnect;
`reset` settles a queued write with a `network` error. The state field
`offline` is optional, so existing snapshots are unchanged until it is set.
`better-supabase/next/offline` binds them to `useOffline()` from
`next/offline` with `useBlockQuery` and `useBlockMutation`, seeding the
controller from the first value so a component that mounts offline never starts
a read. The offline controllers live in `blocks/block-offline.ts`, apart from the
plain ones, and the hooks sit in their own subpath: Turbopack keeps the code of
an unused export of a client entry, so putting them in `next/client` added about
700 bytes to the first load of every route of an app that only used
`useSessionChange`, and the next-build baseline never grows.

`init` renders `templates-next.ts` into the Next.js integration: the layout the
check script lists, the PWA files and the Web Push keys. The output is committed
under `tests/init-fixture/nextjs`, and `tests/cli/init-fixture.test.ts`
compares it byte for byte (`INIT_FIXTURE_UPDATE=1` rewrites it). The fixture is
outside the formatter and the linter, since they would rewrite it.

## Consequences

Record and list controllers in `src/react` are not covered yet: they keep their
own fetch state. The `.env.example` entry uses the `create` policy, so an app
that already has the file adds the two keys by hand.
