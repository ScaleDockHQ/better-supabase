---
"better-supabase": minor
---

`gen` writes one module per table and one slice module for the block config by default. The server's schema moves to `generated-schema.ts`, so `import { schema } from "./generated"` becomes `import { schema } from "./generated-schema"`; `gen.tableModules: false` and `gen.blockModules: false` keep the single module. `better-supabase codemod table-modules` rewrites the import and, in a `"use client"` file, reads `bsb.db.customers` as `bsb.table(customersTable)`. `init` writes the new import, and `gen --metadata` and the content mapper keep one module.
