---
"better-supabase": minor
---

The `bulk` block is `bulk-actions`. Import from `better-supabase/blocks/bulk-actions`, name it `blocks["bulk-actions"]`, and use `db.$blocks.bulkActions`. Run `better-supabase codemod naming` to rewrite imports and the config key, then `upgrade`; the migration renames the block's registry row and its permission keys in place, so roles and overrides keep their grants. The run keeps its names: the `bulk_runs` table, `start_bulk`, `BulkRun` and the `BULK_*` hints.

| Old                                     | New                                                          |
| --------------------------------------- | ------------------------------------------------------------ |
| `better-supabase/blocks/bulk`           | `better-supabase/blocks/bulk-actions`                        |
| `blocks.bulk`                           | `blocks["bulk-actions"]`                                     |
| `createBulk`, `bulkBlock`, `bulkEvents` | `createBulkActions`, `bulkActionsBlock`, `bulkActionsEvents` |
| `Bulk`, `BulkOptions`, `BulkEvents`     | `BulkActions`, `BulkActionsOptions`, `BulkActionsEvents`     |
| `bulk.run`, `bulk.*`                    | `bulk_actions.run`, `bulk_actions.*`                         |
