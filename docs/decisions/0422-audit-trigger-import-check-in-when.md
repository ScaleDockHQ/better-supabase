# 0422: Check the import summary mode in the audit trigger's when clause

- Status: accepted
- Date: 2026-11-08
- Amends: 0141

## Context

With `imports.audit: summary`, `audit_row_change` returned for every row of an
import. The check ran inside the function, after PostgreSQL had started it and
after its declarations had turned the old and new row into `jsonb`. A batch of
thousands of rows paid for a PL/pgSQL call and two `to_jsonb` conversions per
row to write nothing.

## Decision

Every row audit trigger the library writes (`audit(...)`, the static
`bsb_audit` trigger of a block table and the update variant for `ignore`) has
`when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary')`.
`import_run()` reports a session only to the service role, so a user who sets the
flag keeps being audited. The check stays inside the function too, for triggers
installed before this change. Doctor and the audit coverage reader accept a
`when` clause between `for each row` and `execute function`.

## Alternatives considered

- Default `audit.statement` on for import targets: a breaking default that
  changes what an audited import table writes in `rows` mode. Deferred to its own
  decision with a migration note.
- A new SQL function for the condition: `import_run()` is already executable by
  the API roles, so the condition is inlined and no definer function is added.

## Consequences

A summary import starts no audit function per row (pgTAP `audit_import_when`).
`better-supabase upgrade` rewrites every module that registers block-table audit
triggers, and the next schema migration drops and creates each `bsb_audit`
trigger. No data migration is needed.
