# 0600: Filter subject cascade deletes on the tenant

- Status: accepted
- Date: 2026-11-10
- Amends: 0424

## Context

`attachments_subject_deleted` deleted on `subject_type` and `subject_id` only, while the table's
subject index leads with the tenant, so each deleted subject row scanned the table. The comments
cascade compared `tenant::text = v_tenant`, which can't use an index either. `documents` has a
`unique (subject_type, subject_id, name)` index, so its cascade already reads an index and stays
as it is.

## Decision

`subjectCascades` takes a `remove` function that receives `tenantAnd(alias, column)`. Attachments,
reactions, reviews (and its stats) and comments pass `{ tenant: true }`, so the trigger passes the
subject row's tenant and the delete adds `and <column> = v_tenant::<id type>`. A subject with
`tenant: false` gets `v_tenant` null and the two-column delete. Approvals, relations and
collections keep the old predicate: approvals has no subject index and the other two have no
tenant column to lead with.

## Consequences

A scale test (`scale_subject_cascade`) deletes 1,000 products with 12,000 attachments in about
130 ms, keeps another tenant's attachment with the same subject id, and checks that the delete
plan has no sequential scan. I did not measure the old statement for the comparison.
Run `better-supabase upgrade` and generate the migration.
