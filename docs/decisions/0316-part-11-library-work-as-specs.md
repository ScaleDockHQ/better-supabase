# 0316: Record the Part 11 library work as specs

- Status: accepted
- Date: 2026-11-07
- Amends: 0310

## Context

Part 11 needs changes in `packages/better-supabase` and `packages/next-config`
that the example-app work could not make: a generated `AuthGate`, a `stage`
option on `bsb.cached`, a `next/proxy` subpath, taint, the offline controllers
with the PWA files, and an `init` fixture of the feature-sliced layout.

## Decision

`docs/agents/nextjs.md`, "Library specs", states each change with the files it
touches, the behavior, the invariants it must keep (ADR 0095, 0116 and 0117, the
WinterTC entry rule, the size baselines) and the test that proves it, so a later
worker can build it without reading the plan. `scripts/app-architecture-allow.json`
already lists the fixture path as a pending root.

## Consequences

Nothing ships from this ADR. Each spec becomes its own change with a changeset,
an export snapshot update where a subpath is added, and a docs page.
