---
"better-supabase": minor
---

Keeps block code out of the browser bundle. `gen` writes `blocks.config.ts` (data only), the
scaffold splits `index.ts` into `app.ts` and a server `index.ts`, and `gen.clientBlocks` lists
the instances the browser needs, written to `blocks.client.ts`. Generated data hooks use the new
`defineListHook` and `defineOneHook`, and the block and schema definers are annotated as side-effect
free so bundlers drop what the app doesn't import. Run `better-supabase codemod 0.53`, then
`gen`. `doctor` rule BS511 flags a client component that imports `blocks.generated`, `providers.ts` or
`defineBlocks`.

| Before                                                                | After                                                                                     |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `import { blockConfig } from "./blocks.generated"` in client code     | `import { blockConfig } from "./blocks.config"`                                           |
| `createClient(betterSupabase, ...)` in `client.ts`                    | `createClient(app, { blocks: blockConfig })` with `app` from `app.ts`                     |
| `export const { useList: useX, useOne: useY } = defineDataHooks(...)` | `useX = defineListHook(...)`, `useY = defineOneHook(...)` (`defineDataHooks` still works) |
