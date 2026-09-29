# Troubleshooting

Start with `pnpm better-supabase doctor`. It checks the database, RLS,
`supabase/config.toml` and env files, and links every finding to its fix.

## By `DbError` kind

Branch on `result.error.kind`, not on the message.

| Kind | Usual cause | Fix |
| --- | --- | --- |
| `not_found` | The row doesn't exist, or RLS hides it from this user | Check the policy with an `asUser` test before assuming the row is gone |
| `unauthorized` | No valid session or token | Get `db` from the adapter for this request |
| `forbidden` | RLS or a grant rejected the write | Fix the policy or the grant; don't switch to `server.admin()` |
| `conflict` | Unique violation | Use `upsert`, or return the error to the caller |
| `foreign_key` | Referenced row missing, or still referenced on delete | Create the parent first, or delete children |
| `not_null`, `check`, `exclusion` | A constraint rejected the row | Validate input earlier with the `validation()` plugin |
| `invalid_input` | Postgres couldn't parse a value (bad uuid, enum) | Validate before the call |
| `validation` | A Standard Schema rejected the input; see `issues` | Show the issues to the user |
| `invalid_request` | The query can't run over PostgREST (for example a relation filter on `update`) | Read the keys first, or use a database function or `better-supabase/postgres` |
| `multiple_rows` | `findUnique` or a single-row write matched more than one row | Filter by a unique key |
| `stale` | `update(..., { expect })` found a newer row | Reload the row and retry |
| `serialization`, `timeout`, `network`, `rate_limited` | Transient | Retry with backoff, or surface the error |
| `raised` | A database function raised an exception | Read `message` and `code` from the function |

## Other symptoms

- Types don't match the database: run `pnpm better-supabase gen`, then
  `gen --check` in CI.
- A column name is `snake_case` in one place and `camelCase` in another:
  repositories use the configured casing, `$client` and `$sql` use database
  names.
- Every request calls the Auth server: the token is being refreshed outside
  the proxy. Refresh happens only in the Next.js proxy (`next.proxy`).
- Tests pass with the service role but fail as a user: that's the RLS policy.
  Test as users, never with the service role.

Docs: https://bettersupabase.com/docs/cli/doctor.md and
https://bettersupabase.com/docs/guides/limitations.md
