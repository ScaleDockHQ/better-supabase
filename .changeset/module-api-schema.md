---
"better-supabase": minor
---

SQL modules can be called over the Data API without exposing their schema. `sql.modules.<module>.api` (a schema name, or `{ schema, functions }`) makes `sql add` write a `security invoker` entry point in that schema for each module function that `anon` or `authenticated` may execute, with the same name, arguments and grants, and `rpcTransport(supabase, { schema: "api" })` sends every call there. Doctor BS312 still reports an exposed module schema and now points at the option, and the blocks docs no longer suggest exposing the module schema.
