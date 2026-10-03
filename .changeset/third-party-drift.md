---
"better-supabase": minor
---

Values from Postgres and the peer libraries no longer break responses. JSON responses from the server adapters and MCP write `bigint` values as decimal strings. A `timestamptz` or `timestamp` holding `infinity` comes back as an `invalid_value` error (status 500, with `column`) instead of throwing, because Temporal has no infinite value. Temporal values from another realm or a second polyfill copy are recognized by their `Symbol.toStringTag`, and Standard Schema issues with symbol path keys keep the error serializable.

`loadEnv()` reads inline keys from `SUPABASE_JWKS`, as `@supabase/server` does, and verifies with them without fetching `jwksUrl`. The OpenTelemetry plugin writes `db.namespace` as `{database}|{schema}` (`postgres|public` by default, `otel({ database })` to change it), adds `server.address` and `server.port` from `otel({ server })` to spans and metrics, and sets `db.response.status_code` only for SQLSTATE codes. `BetterQueryMeta` builds on the app's `Register['queryMeta']`, and `send_email`'s `email_data` accepts fields Auth adds later.

Doctor's BS410 reports HTTP auth hooks and checks their `v1,whsec_` secrets, and its custom access token hook event carries `iss` and `amr`. The peer ranges now state what the code needs: `pg >=8.15 <9`, `@tanstack/query-core ^5.62.0`, `@orpc/server >=2.0.0-beta.40 <3`, `hono <5`, `next <17`, `@opentelemetry/api <2`, and `oxfmt 0.66.0`, the version `@supabase/postgrest-typegen` pins; the `gen` notice and docs show how to allow a newer oxfmt.
