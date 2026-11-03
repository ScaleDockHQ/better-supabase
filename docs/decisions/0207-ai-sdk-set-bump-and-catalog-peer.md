# 0207: Move the AI SDK set to ai 7.0.159 and add @workflow/vitest and @chat-adapter/catalog

- Status: accepted
- Date: 2026-11-03

## Context

The AI SDK packages share one `@ai-sdk/provider-utils`, and `@ai-sdk/workflow`
pins `ai` exactly, so `ai`, `@ai-sdk/react` and `@ai-sdk/workflow` move
together. The plan for the ai-sdk and workflow gaps needs the newer message,
tool approval and workflow chat transport types, tests that run workflows in
Vitest, and the Chat SDK adapter catalog for the chat-sdk helpers.

## Decision

- The default catalog moves `ai` from 7.0.153 to 7.0.159, `@ai-sdk/react` from
  4.0.157 to 4.0.163 and `@ai-sdk/workflow` from 2.0.85 to 2.0.91. The peer
  ranges stay `>=7 <8`, `>=4 <5` and `>=2 <3`.
- The set shares one `@ai-sdk/provider-utils` (5.0.72 for these releases), so
  `@ai-sdk/mcp` moves from 2.0.84 to 2.0.88, `@ai-sdk/anthropic` from 4.0.88 to
  4.0.94 and `@ai-sdk/sandbox-vercel` from 1.0.164 to 1.0.170. Left behind, they
  kept a second provider-utils copy and the type tests failed on incompatible
  schema types. 2.0.90, 4.0.96 and 1.0.173 are newer but need provider-utils
  5.0.74, which `ai` 7.0.159 does not use.
- `@workflow/vitest` 5.0.6 is a devDependency of `better-supabase`, next to
  `@workflow/world-testing` at the same release.
- `@chat-adapter/catalog` 4.43.0 is a devDependency and an optional peer with
  the range `>=4.43 <5` and `peerDependenciesMeta` optional (ADR 0036). It is
  loaded on first use, never imported at the top of a runtime entry, so
  `tests/optional-peers.test.ts` lists it and `optional-peers.test-d.ts` checks
  the functions we read. The lazy-imports rule and the docs peers page name it.
- All versions are exact catalog pins and respect `minimumReleaseAge`.
  `@ai-sdk/sandbox-vercel` 1.0.171 was still inside the window, so the pin is
  1.0.170, the previous release.

## Alternatives considered

- Leave the pins where they were: the gaps need fields that only the newer
  releases carry.
- Make `@chat-adapter/catalog` a dependency: the core allows no runtime
  dependency beyond the Supabase packages and `@standard-schema/spec`.
- Vendor the catalog data: it would go stale on every adapter release.

## Consequences

The three AI SDK pins stay in lockstep on later bumps. `@chat-adapter/catalog`
must stay in the same minor family as `chat`, so revisit the range when `chat`
moves to 5.
