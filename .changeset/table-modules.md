---
"better-supabase": minor
---

`gen.tableModules: true` writes one module per table, `tables/<table>.ts`, and moves the server's schema to `generated-schema.ts`. The generated module exports `clientSchema` for a browser client that registers the tables it uses: `bsb.table(customersTable)` returns a table's repository, the generated hooks read through it, and `defineListQuery` accepts a table module in place of a table name. A page then ships only the tables it imports. `defineTable` and `TableModule` are new exports, `SchemaMeta.lazyTables` marks a schema whose tables register on use, and `BetterSupabase.registerTable` adds one. Generated record files import `permissions` from `blocks.config.ts` instead of `blocks.generated.ts`, so a record no longer loads every installed block in the browser; run `better-supabase gen` to rewrite them.
