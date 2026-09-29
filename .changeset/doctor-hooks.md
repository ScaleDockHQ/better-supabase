---
'better-supabase': minor
---

Auth hook checks in `doctor`. Snapshots now record the functions behind every enabled
`[auth.hook.*]` with a `pg-functions://` URI, in any schema, with their execute and schema-usage
grants. BS404 (error) reports a hook function that doesn't exist, that `supabase_auth_admin` can't
call, or that `authenticated`, `anon` or `public` can call, and lists the fixing SQL. BS405
(warning) reports a custom access token hook that isn't `stable` or lacks `set search_path = ''`.
With `--as <user id>`, BS405 also calls the hook for that user in a rolled-back transaction and
warns when the claims it returns are over 2 KB.
