---
"better-supabase": patch
---

The `better-supabase` skill covers 0.36 to 0.39: `codemod 0.37` after upgrading from 0.35, doctor's BS607 version check, `bsb.contextClient(ctx.auth)` for a supabase-js client on the server, writing block tables through the block client with your own columns in `fields` (BS351), and encrypting secret columns (BS352). BS352 now names the `tables.<name>.columns` config key instead of `appTables`, and the migration guides say that 0.38 and 0.39 only add options.
