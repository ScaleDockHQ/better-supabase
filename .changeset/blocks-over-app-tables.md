---
"better-supabase": minor
---

Blocks laid over your own tables now behave as they do on their own tables.

- Numbering: a block that numbers its own row (tasks, deals, quotes, invoices, donations) marks the number it took from `next_number` for the transaction, so a `numbering` entity with a `table` accepts it instead of refusing it with `NUMBER_MANUAL`, and the number is assigned once.
- Rows: read functions of tasks, employees, hiring, pipelines, quotes and invoices return a row of your table keyed as on the block's table. A renamed column also comes back under the block's name (`tenant_id` when the tenant column is `organization_id`), and a mapped value as its label, so the TypeScript clients parse it. Bug fix: `organizationId` and renamed fields used to read as missing.
- Extra columns: `insertExtraColumns` writes every extra column in the insert, with the type's `default` for a key the call leaves out, so a check across extra columns holds when the row is created. Tasks, quote, invoice and deal lines, employee contracts and private details, teams, tags, saved views, hiring jobs and calendars use it.
- `add_employee_contract` keeps your contract table's currency default when `attrs` has no `currency`.
- Value maps: `blocks.<name>.values` now applies in the catalog, quotes, invoices, inventory, orders and shipments modules: status and kind literals in functions, policies and reads, with list values and `null` for a label your app lacks. `products.kind` and the status of stock reservations and transfers are typed columns. A quote whose map sets `viewed: null` keeps its status when the link is opened.
- Calendar: `columns.rules.id` may be `null` for a rules table keyed by its event, and `options.ruleDialect` (`weekdays: "lower"`, `monthDay: "scalar"`, `ordinal: { weekday, position }`) reads and writes structured rules in your table's shape.

Generated SQL changes only where these apply: blocks over your tables, a renamed tenant column, extra columns and numbered entities with a table.
