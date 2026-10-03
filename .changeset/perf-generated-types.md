---
"better-supabase": minor
---

Generated files and types that cost less to check and to bundle.

- Breaking: `gen` writes the schema metadata to `generated.meta.js` with a
  `generated.meta.d.ts` next to the main module, which imports it. TypeScript
  reads the metadata as `SchemaMeta` instead of checking a large object
  literal, which cuts check time and editor memory on large schemas. Run
  `better-supabase gen` and commit both new files.
- Breaking: `BetterPostgres` gains `executorFor(claims)`, and `createServer`
  uses it for `ctx.sql` and `actingAs()`. Apps that don't pass `postgres`
  no longer bundle the SQL compiler; the Next.js, Hono, oRPC, edge and MCP
  entries are about 5 KB gzip smaller. A custom `BetterPostgres` implements
  `executorFor` as `postgresExecutor(asUser(claims))`.
- Reads without `select` or `include` return the row type directly, which
  removes about a quarter of the type instantiations a query costs.
- The build marks library modules as side-effect free and annotates
  module-level objects as pure, so bundlers drop the parts an app doesn't use.
