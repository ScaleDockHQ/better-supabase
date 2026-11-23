---
"better-supabase": minor
---

Doctor adds BS429 (info), which lists the actions, write routes, resource actions and MCP tools that check a permission and set no `enforcement`, so each one's authorizer check runs as `definer` and reads the authorization version live. It adds BS731 (warning) for each SQL file the schema reader rejects, with the file, line, column and the Postgres version whose grammar rejected it; doctor used to skip such a file without a word. BS409 now warns when `blocks.permissions.disabled.user` or `.tenant` overrides the provider's `suspension` with the other form, since a missing row lets the subject through with a column and disables it with a row. `SchemaReadError` gains `major`, and the `gen`, config SQL and codemod messages name the grammar.
