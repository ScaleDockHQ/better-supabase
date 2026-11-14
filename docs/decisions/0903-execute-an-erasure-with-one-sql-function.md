# 0903: Execute an erasure with one SQL function

- Status: accepted
- Date: 2026-11-14

## Context

ADR 0899 added `subjectAccessPlan`, which lists what an erasure covers, but
nothing ran it (EX-1310). `fulfil_data_subject_request` only records that the
app erased the data. The plan lives in TypeScript manifests, and an erasure has
to run inside the database, in one transaction, with the legal hold check next
to the rows.

## Decision

A table's SQL spec declares `lifecycle.erase` (`mode`: `delete`, `anonymize` or
`keep`; `personal`: the nullable columns an `anonymize` sets to null;
`retention`: the hold kind). `data-lifecycle-erase.ts` generates
`erase_data_subject(request_id)` over every installed module table that
declares it, the same way the record export reads `lifecycle` entries. It
needs a verified, open erasure request that names a record, and the caller needs
`data_lifecycle.export` or the service role. For each table it checks
`is_held(retention)` for the request's tenant. A held table is left untouched and
reported under `held`; the others are deleted (`removed`), blanked (`blanked`) or
counted (`kept`). Every statement is limited to the request's tenant, subject
type and subject id. The request stays open, so `fulfil_data_subject_request`
still closes it with a resolution.

The client method `executeErasure({ requestId })` returns the four groups as
counts by `schema.table`. `tests/sql/modules/data-lifecycle-erase.test.ts` fails
when a manifest entity declares an erase mode its SQL table does not, and when an
append-only entity's table declares `delete`. Tables that declare it today:
`consents` and `field_changes` (`anonymize`), `data_subject_requests` (`keep`)
and `consent_signals` (`delete`). `consent` no longer lists `givenByContact` as
personal data, because a representative's consent must keep its contact (a check
constraint) and the contact is its own record.

## Alternatives considered

Passing the plan to a generic function as JSON: a caller could name any table.
Running the erasure in the client from the plan: it takes many round trips, cannot
share a transaction and checks the hold apart from the rows.

## Consequences

An erasure runs in one transaction and reports what it did, and an audit
invariant (append-only rows never deleted) is checked in CI. The function adds
six counted security-definer functions to `data-lifecycle` in the practices
baseline. Tables of other blocks adopt `lifecycle.erase` as lane I and the block
owners reach them; until then an erasure reports only the tables above.
