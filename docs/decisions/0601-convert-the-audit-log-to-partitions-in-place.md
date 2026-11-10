# 0601: Convert the audit log to monthly partitions with a procedure

- Status: accepted
- Date: 2026-11-10

## Context

`options.partitioned` applied only when the module created the log. A log of millions of
entries stayed unpartitioned, and its retention kept deleting rows. The plan asked for a
conversion with no downtime.

## Decision

With the option on, the audit module writes `convert_audit_log_to_partitioned(batch_size,
drop_old)`, a procedure that commits between batches. It builds the partitioned table and
its indexes (the idempotency key gains `occurred_at`) while the old table takes writes, copies
by id in batches, then locks the old table in `exclusive` mode (writes wait, reads continue),
copies the last rows, swaps the names, and recreates the policies, grants and triggers from the
catalog. The old table stays as `<name>_unpartitioned`. The log is append-only, so a row is
copied once. A rerun resumes from the largest id already copied.

## Alternatives considered

- A CLI command (`db partition audit`) that renames the table and re-runs the module SQL: the
  history would be missing from reads for the whole copy.
- Turning the option on in the fixture: pg-delta would plan a drop of the table.
- A CLI wrapper is not part of this change; the procedure is called with `call`.

## Consequences

Measured on 5.0M entries with a second connection inserting every 5 ms: 30 s for the whole
conversion, 4,646 rows written meanwhile, none failed, none lost, the sequence continues, a
30-day query reads two partitions and prunes 23. The write lock lasts for the last batch and
the renames. Dependent foreign keys on the old table are dropped (the restricted details table
has none once the log is partitioned).
