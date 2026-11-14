# 0899: Plan subject access and erasure from the manifest

- Status: accepted
- Date: 2026-11-14

## Context

18 blocks mention erasure, and no call collects or erases a person's rows across
blocks (EX-1310). `data-lifecycle` exports and purges the tables of installed
modules and handles data subject requests, but it does not know which columns of
which entity hold personal data. ADR 0689 reserved `personalData` and
`retention` on the entity surface without a reader. GDPR Art. 17 allows an
erasure to keep what a legal duty requires, and the audit and field-history
tables are append-only, so a blind delete would break the trail.

## Decision

The entity surface gains `subjectColumn` (the column that names the person) and
`erase` (`delete`, `anonymize` or `keep`) next to `personalData`.
`subjectAccessPlan(blocks)` in `better-supabase/blocks/data-lifecycle` reads the
declarations and returns the entities an access request collects and an erasure
removes, blanks or keeps. `subjectAccessRequest(lifecycle, input)` opens the data
subject request and returns it with that plan. An entity with `personalData` and
no `subjectColumn`, or an append-only entity that would be deleted, lands in the
plan's `gaps`; `tests/blocks/entity-surface.test.ts` fails when a shipped
manifest has either. `data_subject_request` declares `keep`, `consent` and
`field_history` declare `anonymize`.

## Alternatives considered

A SQL function that scans every table for personal columns: it cannot tell a
legal record from a copy. A `declare module` registry: architecture invariant 2
forbids it.

## Consequences

An app drives export and erasure from the plan instead of a hand-kept table
list. The plan does not run the erasure: the SQL executor per entity is a later
step, and until then the app's purge job reads `erasure`. Record entities
declare their columns as lane I touches them.
