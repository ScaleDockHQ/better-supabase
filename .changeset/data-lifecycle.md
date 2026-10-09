---
"better-supabase": minor
---

The data-lifecycle block (`better-supabase/blocks/data-lifecycle`) exports, anonymizes and purges a tenant's or a user's data across every module table.

- Modules declare their tables, so exports and purges cover every installed module, and `options.autoTables` adds a schema's tenant tables. Exports leave out keys, token hashes and secrets.
- The purge retries referenced tables, stops with `ORGANIZATION_PURGE_BLOCKED` when stuck, and deletes the tenant row last. `createOrganizationPurger({ buckets })` takes path prefixes (`PurgeBucket`).
- `options.anonymize` rules anonymize rows after a retention period (`anonymizeDue()`), and `createDataExporter` takes `format: "csv"`.
