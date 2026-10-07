---
"better-supabase": minor
---

The data-lifecycle module anonymizes records by rule. `sql.modules.data-lifecycle.options.anonymize` takes `{ table, after, from, set, markedBy, unless? }` rules, and the new `better_supabase.anonymize_due(max_rows)` sets the listed columns on every row whose `from` time is older than `after` (unless the `unless` condition on `{row}` holds) and stamps `markedBy`, so each row changes once. The purger has `anonymizeDue()`, and `createOrganizationPurger({ anonymize: true })` also runs it in `job`. A module in custom mode now needs `anonymize_due(integer)` among its functions.
