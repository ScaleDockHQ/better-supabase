---
"better-supabase": minor
---

`lazyPostgres(load)` from `better-supabase/server` gives `sqlSupportStore` its
`admin` and `asUser` connections without importing `pg`. It calls `load` on the
first support query, keeps the connection and retries after a failed load. An app
that creates the store in a module every route imports can load
`better-supabase/postgres` there with a dynamic `import()`, so `pg` leaves the
shared server bundles.
