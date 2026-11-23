# 1198: `db diff` runs with strict coverage, and `--prove` checks the plan on a clone

- Status: accepted
- Date: 2026-11-22

## Context

pg-delta leaves out a user object it cannot model, and by default only warns.
A migration written from such a plan looks complete and fails on a database
built from the migrations. The Supabase CLI 3.2.0 added `--strict-coverage` to
`db diff` and `db schema declarative sync` for this. pg-delta alpha.61 also
exports a proof (`provePlan`) that applies a plan to a clone and reports drift,
lost rows and undeclared rewrites.

## Decision

Under pg-delta, `db diff` stops on the diagnostics `hasBlockingDiagnostics`
returns with strict coverage, writes nothing and lists them in `data.blocking`.
`--no-strict-coverage` restores the warning. The Supabase CLI path passes
`--strict-coverage` to `declarative sync`. `--prove` clones the local stack with
`create database ... template` (it disconnects the stack's services first),
runs `provePlan` against the files' desired state and refuses a plan that fails.
A stack that cannot be cloned skips the proof with the reason, never the diff.
The in-stack diff also reads `_custom/` with pg-delta's `listCustomFiles` (from
`@supabase/pg-delta/frontends`, loaded only when the folder exists) and reports
the files with no delivery directive or a dangling one, without failing.

## Consequences

A diff that would have dropped an object silently now stops with the object's
name. The proof is opt in because it touches the stack's connections. A parity
run compares the CLI's bundled pg-delta with the pinned alpha on the validation
projects (ADR 1199).
