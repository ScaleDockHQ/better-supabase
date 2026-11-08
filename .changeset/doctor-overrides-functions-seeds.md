---
"better-supabase": minor
---

`better-supabase doctor` adds four checks. BS394 holds a function that overrides a block function against the module's current text: write `-- @bsb-override-of <schema.fn> <hash>` above your own `create function`, and doctor prints the new hash when the module changes (BS369 no longer reports a tagged function). BS395 flags `verify_jwt = false` for an Edge Function that uses `auth: 'user'`, except `mcp`. BS396 flags ten or more single-row inserts into one table in a seed file. BS397 flags an `insert`, `update` or `delete` in a schema file for a table a migration or block data file also writes. `better-supabase upgrade` rewrites no module and no data moves.
