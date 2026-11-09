# 0421: Index search records once per import batch

- Status: accepted
- Date: 2026-11-08
- Amends: 0141

## Context

Every search index trigger called `search_refresh` for its row, and every watch
trigger called it again for each record it reached. A batch that inserts a row
and then renames it, or that touches one parent from many children, indexed the
same record several times. On a 1,000-row batch of one table with an insert and
a rename per row, `search_refresh` ran 2,000 times in 500 ms. The watch triggers
were also created inside a `do` block that checked for the table.

## Decision

- `import_upsert_batch` sets `better_supabase.search_deferred` for the batch
  when the search module is installed. While it is on, the index and watch
  triggers call `search_enqueue`, which notes `type` and `id` once in the
  transaction-local setting `better_supabase.search_dirty`. The batch calls
  `search_refresh_dirty` before it restores the caller's settings, so each
  noted record is indexed once. A dry run drops the notes with its
  subtransaction. Code that begins an import session itself does not set the
  flag, so its writes still index at once.
- `search_refresh` rewrites a document only when the tenant, title, body, URL or
  description changed.
- Watch triggers are static `create trigger` statements. A watched app table or
  later block table gets its trigger from the table's own file, like the index
  triggers. `watch[].columns` limits the update trigger to named columns; without
  it any update re-indexes, as before. The search `do` block is gone.

## Alternatives considered

- A `search_dirty` table: a table needs a name in the catalog, a policy, an
  export rule and a purge, for rows that live inside one transaction. A temp
  table is invisible to `supabase db lint` (a registry test forbids it).
- A tenant-led primary key on `search_documents`: refresh finds a record by type
  and id without the tenant, so it would need a second index to stay as fast.
  Deferred until a tenant-scoped read needs it.
- A statement-level trigger variant: deferred until the per-batch flush is
  measured insufficient.

## Consequences

Importing a record that changes more than once in a batch costs one refresh.
`better-supabase upgrade` rewrites the `search` and `imports` modules; no data
migration is needed. A watched table the schema creates after the module files
and that is neither an app table nor a block table gets no trigger from the
library; doctor should say so (listed in the report for the doctor worker).
