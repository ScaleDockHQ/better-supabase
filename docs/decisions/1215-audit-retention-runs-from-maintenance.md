# 1215: Audit retention runs from maintenance

- Status: accepted
- Date: 2026-11-23

## Context

The audit log grows with every audited write. `purge_audit_log` and the
partition helpers existed, but nothing called them unless the app scheduled
`purge_audit_log` itself, and doctor rule BS389 only reminded it to. An adopter
reported a log that had grown for a year because nobody had wired the job.
Exemptions from audit coverage (BS315) were also invisible once written: a
reviewer could not tell whether an exempt table had ever been audited.

## Decision

The audit block takes `options.retention: { keep, onExpire, batch }`. Unset
keeps every entry, as before, so nothing is deleted by default. With it set,
the block installs `housekeeping` and contributes an `audit_retention` job to
`maintenance()`, which runs `audit_retention_run()` every hour. The function
deletes up to `batch` entries (default 10,000) past `keep` through
`purge_audit_log`, so the data-lifecycle policies, legal holds and the
`audit_retention` hook still apply, and on a partitioned log it calls
`maintain_partitions()`. `onExpire: "detach"` first detaches each month wholly
past `keep` from a partitioned log the block owns and leaves the table for the
app to archive. An adopted or unpartitioned log refuses `detach` at render
time: partitioning needs a log the block creates.

BS389 stops when `retention` is set. A new live rule, BS639 (info), lists each
table BS315 skips with its reason and the time of its last audit entry, or
`never`.

## Alternatives considered

A default retention of a year. Deleting audit entries is a compliance decision,
and some apps must keep them longer, so the library does not choose one.

Detach on every partitioned log, without an option. Many apps want the rows
gone, and a detached table they never archive is a slower leak than the log.

A separate pg_cron job per block. `maintenance()` already records each job's
outcome and runs without pg_cron from the jobs drain route.

## Consequences

An app turns retention on with one option and sees its runs in
`maintenance_jobs`. The audit block moves to version 16; the upgrade is
additive. A detached month keeps its restricted rows next to it, so the app
archives both. Revisit if a log needs per-tenant detach, which partitions by
month cannot express.
