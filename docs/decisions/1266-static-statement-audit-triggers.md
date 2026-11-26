# 1266: Static statement audit triggers

- Status: accepted
- Date: 2026-11-26

## Context

`audit(statement => true)` creates three statement triggers that write every
row of one statement in a single insert (ADR 0612). A schema diff keeps a
`create trigger` and skips a top-level `select better_supabase.audit(...)`, so
an app that wants statement mode on its own tables has to write the triggers by
hand, and doctor never reads them as a registration.

Block entity tables stay on deferred row triggers. Postgres only defers
constraint triggers, and those are row-level. A statement trigger would fire
before the block function's `audit_event` sets `bsb.recorded`, so each row
would be written twice. Bulk writes to block tables already use import summary
mode.

## Decision

`auditStatementTriggers` prints the three static triggers
`audit()` creates, and `audit()` prints them from the same helper.
`better-supabase codemod audit-statement <schema.table...>` rewrites a table's
`bsb_audit` row trigger, or its `audit()` call, into those triggers in the
schema file. It refuses a table with no primary key and the `deferred`,
`tenant_path` and `tenant_function` settings, the same cases `audit()` refuses.

The schema reader treats a `bsb_audit_stmt_*` trigger that calls
`audit_statement_change` as a registration, so its `ignore` and `redact` count.
Doctor BS651 reports a table that has both a row trigger and statement
triggers.

A statement insert of many log rows cannot see its own earlier rows from the
`bsb_chain` before-row trigger, so those rows would share one chain link.
When the log is chained, the statement function creates a temporary head table
it owns, and `chain_link` links the later rows of that insert from the head:
one lock and one lookup of the previous row per tenant. The trigger ignores a
head table it does not own.

## Alternatives considered

Leaving statement mode as an `audit()` call only. A schema diff drops it on the
next migration, so the app's tables silently return to no statement audit.

Rewriting block entity tables to statement triggers. The deferred row trigger
is what keeps a block function's own entry from being written again.

Inserting the log rows one at a time so the existing chain trigger can see
them. That restores the per-row lock the statement path exists to avoid.

## Consequences

An app writes the three triggers, or runs the codemod, and a schema diff keeps
them. A chained log stays verifiable after a statement write. Block tables are
unchanged.
