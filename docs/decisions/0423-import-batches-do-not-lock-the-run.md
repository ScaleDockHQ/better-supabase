# 0423: Import batches do not lock the run, and their size adapts

- Status: accepted
- Date: 2026-11-08
- Amends: 0141

## Context

`import_upsert_batch` read the run with `for update` and held the lock for the
whole batch, so a second batch of the same run waited until the first ended. On a
loaded database a batch ran for tens of seconds and a worker pool of any size
wrote one batch at a time. A batch that hit the statement timeout failed the
whole run, and the client had no way to learn a size that fits.

## Decision

- `import_upsert_batch` reads the run without a lock. The status check can see a
  run cancelled a moment ago, which only matters for the batch already in
  flight. The counts update at the end merges in SQL from the locked row, so
  concurrent batches add up.
- `imports.run` halves the batch size after a batch over `targetBatchMs`
  (default 30,000), doubles it up to `maxBatchSize` after a batch under half of
  it, and splits a batch that fails with `57014` in two and sends each half
  again. It returns `suggestedBatchSize`. Without `maxBatchSize` the size never
  grows, so the default behaviour of 200 items per batch stays.
- A `statementTimeout` option on the SQL function is not added: the database
  role's `statement_timeout` already ends a slow batch, and the split handles it.

## Consequences

Workers can write batches of one run in parallel. A cancel lands between batches.
The pgTAP test checks the function body and the summed counts; the lock itself
needs two sessions, so it is verified by the absence of `for update`.
`better-supabase upgrade` rewrites the `imports` module. No data migration is
needed.
