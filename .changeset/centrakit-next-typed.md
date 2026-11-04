---
"better-supabase": minor
---

`createNext` keeps the schema's `Database` type: `ctx.supabase` is `SupabaseClient<Database>` in
`bsb.context()`, `cached()`, `getAccess()` and `action`. `ServerContext`, `BetterNext`, `CachedContext`
and `NextResource` take `D` as a last type parameter that defaults to `any`, so code that names them
keeps compiling.

`bsb.action` takes a `bound` schema for the leading arguments of `action.bind(null, id)`, and `tenant`
and the body read the validated tuple. `bsb.withContext(factory)` returns `cached`, `getAccess` and
`action` with the app's own context, built once per scope. `cached({ readSet })` tags the entry with the
read set's tables.

`gen` warns about bare strings in `blocks.audit.options.exempt`; they become a doctor failure in the
next minor.
