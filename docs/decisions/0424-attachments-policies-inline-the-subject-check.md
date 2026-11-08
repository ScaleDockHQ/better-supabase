# 0424: Inline the subject check in the attachments policies

- Status: accepted
- Date: 2026-11-08
- Amends: 0070

## Context

The attachments read and insert policies called `attachment_subject_readable`,
a plpgsql function, once per row. PostgreSQL cannot plan through a plpgsql call,
so every attachment paid a function call and a separate lookup of its subject.
On the local scale fixture (200,000 customers, 40,000 attachments, one tenant)
`select count(*) from attachments` as a member took 32,044 ms.

## Decision

The two policies render the same `case subject_type when ... exists (...)`
expression over the row's columns (`subjectReadable` with the column names
instead of the function parameters), so the planner sees a hashed or indexed
subject lookup. The function stays for callers that pass values. The new
`supabase/tests/scale` folder (D7) holds the fixture and prints the timings as
`SCALE_MS` lines.

## Measured

Same fixture, 200,000 customers and 40,000 attachments: 32,044 ms before,
15,603 ms and 8,734 ms on two later runs of the inlined policy (the machine was
shared). At 60,000 customers and 12,000 attachments: 2,468 ms. Inlining the check
alone left one per-row `can('tenant', "tenant_id", key)` call per attachment inside it.
With the tenant permission checked as a set (`tenantColumn`, ADR 0426) the same
60,000-customer run takes 73 ms.

## Alternatives considered

A `language sql` function would inline, but a subject table a later module
creates must exist when the function is created, which the plpgsql body avoids.
A tenant-led semi join per subject type needs the subject table's tenant set per
statement, which the inline `exists` already gets from its own policy.

## Consequences

`better-supabase upgrade` rewrites the `attachments` module and the next schema
migration replaces two policies. No data migration. The remaining cost scales with
the subject table, so a subject with a large table and a restrictive read
permission is the next target.
