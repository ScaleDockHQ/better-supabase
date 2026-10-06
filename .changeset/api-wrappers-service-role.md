---
"better-supabase": minor
---

`sql.modules.<module>.api` also writes entry points for the module functions granted to `service_role`, granted to `service_role` only, so an app server that reaches the database only through PostgREST calls them with `rpcTransport(serviceClient, { schema: "api" })`. Before, the flags block's `flag_definitions` and `flag_evaluation` had no wrapper, so `createFlagsProvider` over the Data API failed. Wrappers are granted only to `anon`, `authenticated` and `service_role`, and quoted role names in a module's grants are read correctly. `createOutbox` takes a `BlockTransport` in place of the SQL client.
