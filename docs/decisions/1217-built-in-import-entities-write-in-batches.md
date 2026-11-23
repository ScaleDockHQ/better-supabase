# 1217: Four built-in import entities write new rows in one statement

- Status: accepted
- Date: 2026-11-23
- Amends: 0436

## Context

ADR 0436 let an import target name a set-based `batch` function, but no
built-in entity had one, and its only measurement (an app's `customers`) showed
no gain because the time was in that table's triggers. The scale report asked
for each built-in entity to be timed and for `batch` where it pays.

`supabase/tests/scale/scale_import_entity_paths.test.sql` times, for 2,000 new
items per entity, the import through `import_upsert_batch`, a loop over the
entity's one-row write and a single set-based statement over the same rows. On
the local stack (Postgres 17.6):

| Entity             | Import (ms) | One-row loop (ms) | One statement (ms) |
| ------------------ | ----------- | ----------------- | ------------------ |
| `party`            | 253         | 430               | 147                |
| `product`          | 234         | 444               | 249                |
| `supplier_item`    | 298         | 69                | 11                 |
| `asset`            | 297         | 261               | 140                |
| `stock_allocation` | 289         | 252               | 23                 |
| `stock_count`      | 285         | 339               | 27                 |

## Decision

`party`, `product`, `stock_allocation` and `stock_count` gain a `batch`
function: `import_party_batch`, `import_product_batch`,
`import_stock_allocation_batch` and `import_stock_count_batch`. Each writes the
new items it can prove are plain in one statement per table and passes every
other item to the entity's existing write, in order, so the answers keep the
shape ADR 0436 fixed. An item is plain when it has no `subjectId`, its lookups
resolve and nothing in the batch competes with it:

- `party`: a name of at most 300 characters, no `archivedAt` or `billTo`, and
  for a person an email that no other item and no stored person uses.
- `product`: a slug and sku that no other item and no stored row uses, a valid
  price or none, and no `priceFallback`.
- `stock_allocation`: a known variant and location and a quantity above zero.
- `stock_count`: a known location, lines on known variants without bin, lot or
  serial, and each variant once.

The rule from the plan was to add `batch` only where the batch path is at least
20 percent faster than the one-row path. Timed by replacing the `batch`
function with one that raises, so the same import takes the one-row path
(median of four runs, 2,000 new items):

| Entity             | One-row path (ms) | Batch (ms) | Faster by |
| ------------------ | ----------------- | ---------- | --------- |
| `party`            | 547               | 246        | 55 %      |
| `product`          | 406               | 232        | 43 %      |
| `stock_allocation` | 328               | 200        | 39 %      |
| `stock_count`      | 392               | 189        | 52 %      |

`supplier_item` and `asset` get no `batch`: their one-row loop is already below
the import's own per-item cost, so a batch statement cannot win 20 percent.

The statements avoid joins whose row counts the planner has to guess: lookups
are scalar subqueries on the indexed keys, and the functions turn
`enable_nestloop` off, because a common table expression is estimated at a
fixed row count and a nested loop over 2,000 items cost more than a second. The
functions run as security invoker: `import_upsert_batch`, a definer function, is
their only caller, and only `service_role` may execute them.

## Parity

`supabase/tests/database/import_batch_entity_parity.test.sql` imports the same
items twice per entity, once with `batch` and once with it replaced by a
function that raises, and compares counts, errors, the record map and the
written rows. The items include a shared email, sku or variant, a repeated key,
a refused row and a rerun with changes.

## Consequences

`better-supabase upgrade` rewrites the `catalog`, `contacts`, `inventory` and
`imports` modules, and the next schema migration adds the four functions and
the new dispatch. No data migration and no API change. The audit trigger on
`stock_levels` records one change per level a batch touches, not one per item.
