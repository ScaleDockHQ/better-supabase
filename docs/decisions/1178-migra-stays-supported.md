# 1178: Migra stays supported, and pg-delta-only features say so

- Status: accepted
- Date: 2026-11-22

## Context

Supabase CLI 3.2.0 starts new projects on pg-delta, but a project with
`[db.migrations] schema_paths` still diffs with migra. migra drops `comment on`
statements, grants and the `security_invoker` option of views. better-supabase
stores the `@bsb` tags (owner, policies, access) in table comments, so a migra
diff can remove them. BS316 was the only signal.

## Decision

`db diff` keeps both engines, and BS316 stays a warning. A feature only pg-delta
has (`db diff --in-stack`, the baseline of `db squash`) fails under migra with
one message from `src/cli/pg-delta-only.ts`. It names the feature and the two
config lines that switch. Doctor BS713 lists what a migra diff drops from the
schema files: an error for a `comment on` with `@bsb` tags, a warning for grants
and security-invoker views. BS714 reports a module file whose `@bsb-hash` line a
`db pull --declarative` removed, and tells the user to run `gen sql` again.
Live checks on CLI 3.2.0 showed the declarative export keeps nested `_custom`
files and the module files, so `public/_custom/app_tables.sql` doesn't move.

## Consequences

Migra projects keep working and learn what they lose before it happens. The
message is one string, so a new pg-delta-only feature adds one call.
