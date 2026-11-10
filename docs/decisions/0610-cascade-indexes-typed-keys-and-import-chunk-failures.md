# 0610: Index the remaining subject cascades, read keys without jsonb, and let an import chunk fail

- Status: accepted
- Date: 2026-11-10
- Amends: 0600, 0607, 0436

## Context

Four leads of the second audit were still open after ADR 0600, 0606 and 0607.

- The approvals cascade deleted `approval_requests` on `(subject_type, subject_id)`, but the table
  only has a partial unique index on those columns (`where status = 'pending'`) and a
  tenant-led one, so each deleted subject row scanned the table. The relations cascade compared
  both ends without the tenant and had no source-side index.
- Every cascade trigger read the subject's id and tenant with `to_jsonb(old) ->> tg_argv[n]`.
- `drive_retention_sweep` still called `retention_for` and `is_held` per node and label.
- An import batch reported only how many items conflicted, and a chunk a worker could not write
  stayed `pending`, so a queue retried it forever.

## Decision

- `approval_requests` gets `(subject_type, subject_id)`, and `relations` gets
  `(tenant_id, source_type, source_id, kind)` beside the existing target index. The relations
  cascade passes `{ tenant: true }`, so its delete adds the subject row's tenant. Approvals keeps
  the two-column predicate: a tenantless subject type stores its requests without a tenant.
  Collections already index `(subject_type, subject_id)` on each table, and `documents` has its
  unique index, so neither changes.
- `subjectCascades` renders one trigger function per subject type
  (`<module>_subject_deleted_<type>`) that reads `old.<id column>` and `old.<tenant column>`
  directly. A subject with `tenant: false` gets the one-branch delete. The trigger takes no
  arguments any more.
- `drive_retention_sweep` calls `retention_for_memo` and `is_held_memo`.
- `import_upsert_batch` adds `conflictKeys` (the first 100 keys) to its answer when an item
  conflicted, and `UpsertBatchResult.conflictKeys` carries it. `import_chunks.status` accepts
  `failed`. `fail_import_chunk(run, entity, chunk, message)` marks a chunk failed unless it is
  done, `process_import_chunk` answers `{ failed: true, message }` for it, `import_chunk_progress`
  counts it, and `store_import_chunk` makes it pending again. `imports.chunks.fail` wraps it.

## Measured

On a reset local stack, 60,000 products with 12,000 approval requests and 12,000 relations,
deleting 1,000 subject rows (`scale_subject_cascade_rest`): 2,029 ms before, 191 ms after. The
before plan scans both tables; the test now asserts that both deletes read an index.

Reading two columns of a 60,000-row table in plpgsql: 360 ms through `to_jsonb(row) ->> name`,
14 ms through `row.column`. Deleting 60,000 products end to end moved from 4.0 s and 9.2 s to
3.4 s, 6.4 s and 6.3 s on a machine that was busy with other agents, so that number does not
separate the two. I did not time the drive sweep: its pgTAP file (`drive_retention_changes`)
passes with the memo functions, and the sweep is bounded by `batch_size`.

## Not done

- Statement-level realtime broadcasts, the deferred search list and the typed key read in the
  search and sessions triggers: the search trigger reads the column name from `tg_argv` per
  type, so it needs the same per-type function and was not changed here.
- Other subject read-policy families (ADR 0606). `field_history` reads through a function with
  one constant subject and a limit of 500, not a policy, so it costs one `can_subject` call per
  returned row at most. The rest (deals, consents, sla, observations, care plans, medications,
  funding, deadlines, knowledge) need the recursion check of ADR 0606 each.
- `webhooks-in` and `reviews` render the new per-type functions only in installs that use them;
  the fixture does not.

## Consequences

`better-supabase upgrade` rewrites seven modules; the migration drops the generic
`*_subject_deleted` functions and creates one per subject type. A subject type so long that the function name passes 63 characters makes the render throw instead of letting Postgres truncate it.
