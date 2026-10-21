# 0061: Generate typed helpers for blocks and keep their libraries optional peers

- Status: accepted
- Date: 2026-10-21

## Context

With block names resolved once (ADR 0060), app code still repeated them as
strings: permission keys in `can()`, event types in sinks, URLs, realtime
topics and storage paths. Forms re-declared block inputs by hand, list pages
parsed search params by hand, and every app wrote its own query keys and
invalidation for block clients. Invariant 1 keeps the core free of runtime
dependencies, so any helper built on zod, valibot, nuqs, TanStack Query or
oRPC has to stay out of the library's dependency list.

## Decision

The generator model and `blocks.generated.ts` carry what app code needs, and
the library adds helpers that read them:

- **Generator model:** `GeneratorModel` gains `functions` (typed args, return
  type, set flag, volatility) and `blocks` (each installed block with its
  renamed client export, entities, URLs and input schemas). Both fields are
  additive, so `apiVersion` stays 1. Block data reaches the CLI through the
  preset catalog, so the CLI never imports a block module.
- **Input schemas:** `entitySchema<T>(spec)` builds a Standard Schema with
  JSON Schema conversion and no validation library, and its spec must name
  every key of `T`. Entity blocks carry input, change and list filter
  schemas in `defineBlock`'s `schemas` field.
- **Schema generators:** zod, valibot, `standardSchema` and `jsonSchema` write
  function argument (and row or scalar result) schemas and the renamed block
  input schemas (`taskInput`). The `fieldMeta` option exports labels,
  required flags, enum options and check bounds.
- **Name constants:** `blocks.generated.ts` exports `permissions`,
  `PermissionKey`, `RoleName`, `blockEvents`, `blockEventSchemas`, `urls`,
  `topics`, `paths`, `SettingKey` and `MeterName`. Every adapter takes the
  authorizer's permission type, so `defineAuthorizer<PermissionKey>()` checks
  each key at compile time.
- **Runtime helpers:** `blockQueries` and `invalidateOnBlockEvents` in
  `better-supabase/query`, driven by a manifest `invalidates` map;
  `createBlockQuery`, `createBlockMutation` and `useBlockQuery`,
  `useBlockMutation`, `useBlockEvent` for React, Vue, Svelte and Solid;
  `bs.blockAction` in `better-supabase/next`; `bs.blockRouter` in
  `better-supabase/orpc`.
- **More generators:** `nuqs()` writes search param parsers, a cache, a loader
  and a serializer per table. `factories()` writes typed factories per table
  and per block entity, with `defineFactory` and `factoryTime` in
  `better-supabase/testing`.

zod, valibot, nuqs, `@tanstack/*-query` and `@orpc/*` stay optional peers
with a tested range in `tests/optional-peers.test.ts` (ADR 0036). Generated
files import them; the library's runtime entries don't.

## Alternatives considered

- Make zod the schema language for block inputs. It would add a runtime
  dependency to the core and force one library on every app; Standard
  Schema works with all of them.
- Ship the constants as library exports. Permission keys, event types and
  URLs depend on the app's config, so only generated code can type them.
- Generate one hook per block method. Generic hooks over `ClientOf` cover all
  blocks, renamed or not, without growing the generated file with every
  release.
- Infer read methods for invalidation from names only. The manifest
  `invalidates` map states which events make which reads stale, and
  `renameBlock` renames it with the entities.

## Consequences

App code imports names instead of retyping them, and a renamed block flows
into schemas, query keys, actions and factories without app changes. The
generated file grows with the installed blocks, and each generator needs
snapshot coverage under `tests/generators`. A new block entity must ship
its input schemas with a type test that they match the hand-written types.
We revisit the peer ranges when zod, valibot, nuqs or oRPC ship a major
release.
