---
"better-supabase": minor
---

Cursor pagination no longer skips rows whose sort column is null: the next page follows where Postgres places nulls (last for `asc`, first for `desc`, or the `nulls` option). On the `better-supabase/postgres` executor a cursor over columns that sort the same way and are not nullable compiles to a row comparison such as `(name, id) > ($1, $2)`, which one index range scan can serve.

`defineListQuery`, `defineResource`, `createOpenApi` and the MCP table tools accept `pagination: "cursor"`. The list then takes `after` instead of `page`, returns `nextCursor` and `hasMore`, keeps `size` capped by `maxPageSize`, and documents the cursor in its OpenAPI parameters and JSON Schema. `paginate` and offset lists work as before.
