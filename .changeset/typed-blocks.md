---
"better-supabase": minor
---

Rename a block's entities once in the config and get typed config keys, renamed clients, automatic subjects, generated name constants, input schemas, block hooks and server helpers. See [Typed blocks](https://bettersupabase.com/docs/blocks/typed-blocks).

This release breaks the config and a few exports. Update them as follows:

| Before                                                                                                                  | After                                                                                                                                                |
| ----------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sql: { naming: { tenant: "workspace" } }`                                                                              | `blocks: { tenant: { entities: { organization: "workspace" } } }`                                                                                    |
| `workItemsSubjects()`, `dealsSubjects()`, `partiesSubjects()`, `catalogSubjects()`, `employeesSubjects()` in `subjects` | nothing: installed blocks register their entities as subjects. Remove the spread.                                                                    |
| the helpers' `url` option                                                                                               | `blocks.<name>.entities.<entity>.url`, such as `catalog: { entities: { product: { url: "/products/{id}" } } }`                                       |
| `CatalogSubjectsOptions`, `SqlNaming`                                                                                   | `EntityConfig`, `EntitiesConfig`                                                                                                                     |
| `blockConfig[name].naming` in `blocks.generated.ts`                                                                     | `blockConfig[name].names` (run `better-supabase gen`)                                                                                                |
| `work_item` methods, types and events after `entities: { work_item: "task" }`                                           | `saveWorkItem` becomes `saveTask`, `workItemId` becomes `taskId`, `work_item.created` becomes `task.created`, `work_items.read` becomes `tasks.read` |

A `subjects` entry with the name of a block entity is now an error, and changing `entities` on an installed block makes `sql upgrade` refuse.

- `blocks.<name>.entities` renames a block's nouns in its tables, columns, functions, events, permission keys, subjects and generated types. Every config key under `blocks` is typed from the block's names, and `defineConfig` keeps the config's literal types.
- `renameBlock(block, names)` in `better-supabase/blocks` renames a block client's methods, argument keys, result keys and events. `gen` writes `tasksBlock` and type aliases such as `Task` for each renamed block.
- `blocks.generated.ts` also exports `permissions`, `PermissionKey`, `RoleName`, `blockEvents`, `urls`, `topics` and `paths`.
- The deals, parties, work-items, employees and catalog blocks export Standard Schema input schemas, such as `workItemInputSchema`, `workItemChangeSchema` and `workItemListFilterSchema`.
- The `zod`, `valibot`, `standardSchema` and `jsonSchema` generators write schemas for SQL functions (`<function>Args`, `<function>Result`) and for block entities (`<entity>Input`, `<entity>Change`, `<entity>ListFilter`). `fieldMeta: true` adds labels, required flags, enum options and check bounds.
- `blockQueries(blocks)` and `invalidateOnBlockEvents` in `better-supabase/query` make TanStack Query options for every block method and invalidate reads when a block event arrives.
- `useBlockQuery`, `useBlockMutation` and `useBlockEvent` in `better-supabase/react`, `/vue`, `/svelte` and `/solid` work with any block client, renamed or not.
- `bs.blockAction(client, method, options)` in `better-supabase/next` and `blockRouter(client, options)` in `better-supabase/orpc` expose block methods as server actions and oRPC procedures.
- The `nuqs()` generator writes typed search params for your tables, and the `factories()` generator writes test factories, with `defineFactory` and `factoryTime` in `better-supabase/testing`.
