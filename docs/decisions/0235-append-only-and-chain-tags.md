# 0235: Guard any table with append-only, function-writes and chain tags

- Status: accepted
- Date: 2026-11-05

## Context

The audit block keeps its own log append-only and hash-chained, but an app
that stores legal facts in its own tables had to rebuild both: a trigger that
refuses edits, a revoke of the write privileges and a chain with a verifier.
The chain code was tied to the audit log's columns.

## Decision

The audit module (version 12) installs `better_supabase.append_only(regclass)`,
`function_writes(regclass)` and `chain(regclass, tenant_column)`. The `@bsb`
tags `append-only`, `function-writes` and `chain` add the matching
`select` statement to the schema file, like `audit` does.

`chain` links rows with a before-insert trigger under an advisory lock, per
value of the tenant column (the audit log's tenant column name when the table
has it, else one chain). The table declares `chain_seq`, `prev_hash` and
`row_hash`; `chain()` fails with a hint if they are missing, so the schema
file stays the source of the table. `verify_chain` and
`record_chain_checkpoint` are service role only. `chain()` creates
`better_supabase.chain_checkpoints` on first use.

## Alternatives considered

- Adding the chain columns from `chain()`. It changes the table behind
  `db diff`, which owns the table's shape.
- Moving the audit log onto the shared functions now. The audit log's hashes
  must stay verifiable for existing chains; it keeps `verify_audit_chain` and
  moves only when a hash version lets both coexist (see the evidence bundle
  decision).

## Consequences

Evidence tables need no custom triggers. `append_only` has no purge path, so a
retention job needs a table owner that drops the trigger for its window.
