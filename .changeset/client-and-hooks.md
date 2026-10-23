---
"better-supabase": minor
---

Block instances live on `db`. `.blocks(blockSet)` on the definition puts each instance on the repository object (`db.comments`), running through the same executor as the tables and acting in the active organization. An instance whose name a table already uses stays at `db.$blocks.<instance>`, and `db.$api(fn, args)` calls a function in the API schema. `blocks.generated.ts` exports `blocks`, the block for each instance, so `defineBlocks(blockConfig, blocks)` lists them all.

`gen.hooks` writes `hooks.ts` with a list and a record hook per table (`useCustomers`, `useCustomer`) for React, Vue, Svelte or Solid, built on `defineDataHooks`. The hooks share reads, update cached rows at once on `create`, `update` and `delete`, and roll back on an error. They keep reads in memory by default; `createClient(definition, { engine: queryEngine(queryClient) })` from `better-supabase/query` keeps them in TanStack Query.

The `requireTenant` option and helper are now `requireOrganization`. Run `better-supabase codemod 0.15` to rename them; doctor reports a `requireTenant` that is left.
