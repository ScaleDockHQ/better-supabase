# 0013: Ship SDK adapters whose SDK needs Node as Node-only entries

- Status: accepted
- Date: 2026-10-09

## Context

Invariant 6 keeps runtime entries free of Node built-ins, so they run on
every WinterTC runtime. Two SDK adapters cannot follow it. A Workflow SDK
World persists runs, steps and hooks in Postgres and delivers work from a
long-lived worker; `better-supabase/workflow-sdk/world` builds on
`@workflow/world-postgres`, which imports `pg` and Node built-ins. eve runs
only on Node, and `better-supabase/eve` selects that World for its durable
sessions. ADR 0010 already puts SDK code in adapter subpaths that own no
tables.

## Decision

`workflow-sdk/world` and `eve` are Node-only entries, next to `cli`, `node`,
`nestjs`, `postgres` and `testing` in `NODE_ENTRIES`
(`tests/bundle/bundle.test.ts` and `tests/standards/wintertc.test.ts`).
The World pins `@workflow/world-postgres` and exposes the version as
`WORLD_POSTGRES_VERSION`; a bump regenerates the World DDL and runs the
drift test. The helpers that run anywhere stay in WinterTC entries:
`better-supabase/workflow-sdk` imports only `workflow`, and the blocks the
adapters use (`ai-chat`, `memory`, `knowledge`, `inbox`) import no SDK.
`eve/tools` is loaded through a variable specifier (invariant 12), so
bundlers leave the optional peer out.

## Alternatives considered

- Reimplement the World on WinterTC APIs over PostgREST. The World needs
  transactions and a long-lived worker that PostgREST cannot give, and a
  fork of `@workflow/world-postgres` would drift from the SDK.
- Publish the adapters as separate packages. ADR 0007 keeps one package,
  and the adapters share the blocks' types and transports.
- Leave them out until the SDKs run on edge runtimes. Apps on Node would
  wire the World and eve by hand, without RLS-scoped runs.

## Consequences

Docs and skills mark both entries as Node-only, and the bundle test fails
when a WinterTC entry imports them. Apps on edge runtimes use the WinterTC
helpers and run the World on a Node function. If either SDK gains a WinterTC
build, the entry moves out of `NODE_ENTRIES` in the same release.
