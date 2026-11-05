# 0238: Run the audit log's hash chain on the shared chain tag

- Status: accepted
- Date: 2026-11-05

## Context

Decision 0235 left the audit log on its own chain functions
(`verify_audit_chain`, `audit_checkpoints`, `createAuditChain`) because
existing chains had to stay verifiable. The row hash is the same in both
paths: SHA-256 over the previous hash and the row without `prev_hash` and
`row_hash`. Two chains meant two verifiers, two checkpoint tables and a
proof API that only worked for app tables.

## Decision

The audit module (version 13) renders `options.chain` as the shared `chain`
tag: it adds `chain_seq`, `prev_hash` and `row_hash`, then calls
`better_supabase.chain` on the log with its tenant column. A log from version
12 moves its signed checkpoints into `better_supabase.chain_checkpoints`,
drops `audit_checkpoints` and the old functions, and keeps every stored hash.

`createAuditChain` and its types are removed (breaking). Apps call
`createChain` with `table: "better_supabase.audit_events"` and the log's
tenant column, and get `proof`, evidence bundles and the same checkpoints.
`record_chain_checkpoint` also returns the tenant and the signature.

## Alternatives considered

- Keeping `createAuditChain` as a wrapper. It would hide the table and tenant
  column, and the next change to the shared chain would need two code paths.

## Consequences

Callers of `createAuditChain` rename the import and pass `table` and
`tenantColumn`. A verdict no longer carries `brokenAt`; `seq` identifies the
entry. Checkpoints already signed stay valid because their hashes did not
change.
