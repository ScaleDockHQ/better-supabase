# 0647: Hint at a large audit log in doctor, and keep the data hooks' refetches as they are

- Status: accepted
- Date: 2026-11-10
- Amends: 0601

## Context

The performance audit left two items open. The fixture's audit log is a plain table, and ADR 0601
added a conversion procedure for an app that turns `options.partitioned` on. The data hooks read a
list again after every write and again when the realtime echo of that write arrives. Both items
needed a decision.

## Decision

**Audit log: hint and test, no fixture change.** Doctor rule `BS399` (info, live) reads
`pg_class.reltuples` of `better_supabase.audit_events` when the `audit` block is installed and the
table is still a plain table. At 1,000,000 estimated rows or more it names the option and
`convert_audit_log_to_partitioned()`. A partitioned table, a table that was never analyzed
(`reltuples = -1`) and a saved snapshot report nothing. The fixture keeps the log unpartitioned,
because pg-delta would plan a drop of the table. The conversion has an integration test
(`audit-partition-conversion.integration.test.ts`) that runs in a scratch database on the stack: it
seeds 6,000 rows over 150 days, converts in batches of 500 while a second connection inserts, then
checks that no row is lost, the identity sequence continues, policies and triggers are copied, the
idempotency index gains `occurred_at`, a closed date range reads at most two month partitions, and
a second call changes nothing.

**Data hooks: no change to the engines.** The safe design is a trailing coalesce: an invalidate that
arrives while a read is in flight marks the entry dirty and starts exactly one more read when the
first ends, discarding the first read's data. It never reuses a read that started before the write,
which is what made the earlier attempts unsafe. A realtime echo carries no row ids and no usable
clock, so an echo can't be matched to the write it came from, and a read already in flight can't be
shown to postdate it.

Measured on the memory engine with a prototype of that design (reverted):

| Scenario                                        | Reads today | Reads with a trailing coalesce |
| ----------------------------------------------- | ----------- | ------------------------------ |
| One write, its echo after the read settled      | 2           | 2                              |
| One write, its echo while its read is in flight | 2           | 2, the second one later        |
| Five writes started together                    | 5           | 2                              |

The realtime change feed already batches a burst of events into one call (100 ms debounce), so the
echo costs one read per burst. A single write still costs two reads either way, so "one refetch per
write" is not reachable safely. Only a burst of concurrent writes saves reads, and only on the memory
engine: TanStack Query's `invalidateQueries` would need its own trailing step, and the three local
engines read from a database on the device. The price is latency: the post-write read waits for the
stale one, and the stale read can no longer be discarded early. A caller that writes in bulk can
call one `refetch()` after the batch instead.

`tests/bindings/data-refetch.test.ts` pins what a later change has to keep, on the memory and
TanStack Query engines: read counts per write and per echo, a late older read never overwriting
newer rows, a failed refetch keeping the last rows and recovering, a failed write rolling back and
reading once, and an answer that arrives after the hook stopped following being dropped. The same
skip stands for `realtimeChanges` joining only the tables its hooks watch and for sharing block hook
reads; nothing measured a cost there.

## Alternatives considered

- Reuse a read in flight (`cancelRefetch: false`): returns rows older than the write.
- Skip the echo of our own write: needs the row ids or a commit timestamp compared with a
  server clock, which `DataChanges` doesn't carry.
- Turn partitioning on in the fixture: rejected in ADR 0601; the hint covers real apps.

## Consequences

Apps with a large audit log are told once per doctor run. The hooks behave as before, with their
refetch contract under test.
