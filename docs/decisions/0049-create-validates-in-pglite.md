# 0049: Create validates a design in PGlite

- Status: accepted
- Date: 2026-10-20

## Context

The canvas checks a design with its own rules, and some findings pass those
checks and then fail in Postgres. The repo already ships `@supabase/lite`, an
optional peer that runs PGlite.

## Decision

`better-supabase/create/lite` exports `validateDesign(files)`. It creates a
minimal Supabase prelude (the `anon`, `authenticated`, `service_role` and
`supabase_auth_admin` roles, `auth.users`, the JWT helpers and
`storage.buckets`), applies each generated file in order and returns the
files Postgres rejects. A spike showed the SaaS preset applies cleanly. The
Projects preset needs `pgmq` (jobs) and `btree_gist` (time tracking), which
`@supabase/lite` doesn't load, so those modules are reported as skipped.
Sample rows are not inserted: they are display values, not valid references.
pgTAP and `pg_trgm` are not available through Lite either.

## Alternatives considered

Depending on `@electric-sql/pglite` directly would allow `btree_gist` and
pgTAP, but adds a second optional peer with its own tested range. It stays an
option if skipped modules become common.

## Consequences

Validation needs no credentials and no server, so designs still stay out of
one (ADR 0040). The prelude can drift from the real `auth` schema; a new
column a block reads fails here first and gets added to the prelude.
