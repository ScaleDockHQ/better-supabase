# 0232: Keep the browser client free of block code and let apps opt blocks in

- Status: accepted
- Date: 2026-11-04

## Context

The generated browser `client.ts` imported `betterSupabase` from `index.ts`, which
runs `defineBlocks` over every installed block. Each block manifest holds its
client by value, so a client component pulled every installed block into the
browser bundle. The Next.js example's client bundle was 398 KB minified and
gzipped, about 392 KB of it that chain. Measured in `tests/bundle`, one block
controller costs 1.4 KB and the browser client without blocks costs 63.6 KB.

## Decision

- `gen` writes `blocks.config.ts` with `blockConfig` as data only. `blocks.generated.ts`
  re-exports it. `client.ts` and the generated record files import the data module.
- The scaffold splits `index.ts`: `app.ts` holds `defineSupabase(...)` and the
  server `index.ts` adds `.blocks(blockSet)`. The browser client builds on `app.ts`.
- `gen.clientBlocks` lists the instances the browser uses. `gen` then writes
  `blocks.client.ts` with `clientBlocks`, built from only those manifests.
- Generated data hooks come from `defineListHook` and `defineOneHook` (annotated
  `/*#__PURE__*/`) instead of a destructured `defineDataHooks`, so an unused hook is
  dropped. The block and schema definers carry `/*#__NO_SIDE_EFFECTS__*/`.
- `codemod 0.53` moves `blockConfig` imports, and doctor rule BS511 flags a
  `use client` module that reaches `blocks.generated`, `providers.ts` or `defineBlocks`.

## Alternatives considered

- Lazy manifests with a promise-only client behind a proxy, across about 190
  manifests. A spike showed the remaining cost per listed block is about 2 KB, and
  the change would make every block client method asynchronous to load. The opt-in list
  gets the same result for the browser without that break, so it was not done.
- Moving `description`, `recipes` and `category` out of the manifests. They are 16 KB
  gzipped over all 192 blocks and only matter for an app that installs them all in the
  browser, which `gen.clientBlocks` avoids.
- A new metadata version without `hasDefault` and `description`. The Next.js example's
  `generated.meta.js` is 3.8 KB gzipped, so the saving is under 1 KB.

## Consequences

An app that upgrades runs `better-supabase codemod 0.53`, then `gen`. Browser code that
used `db.<block>` on the client lists the block in `gen.clientBlocks`. Keeping lazy
manifests open leaves room for a later promise-only client API if the per-block cost grows.
