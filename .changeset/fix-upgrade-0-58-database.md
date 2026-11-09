---
"better-supabase": minor
---

Fixes found while upgrading a production app to 0.58. `same_tenant()` lets a row reference a shared row without a tenant, and a deferrable foreign key gets a constraint trigger that runs at commit. The audit module's dynamic insert and the api-keys, flags, tenant switch, usage and knowledge results use the configured tenant column. `clone_task` copies taggings only when the tags block has the table. An `@bsb fields` tag in a multi-line table comment is read, so the feature it turns on stays on. `upgrade` renames the registry row of `time-tracking` and `bulk` instead of adding a second one. `schemaTexts` reads the migrations before the schema files, so an old migration no longer overwrites the final state of the audit tables. The config refuses the former permission keys and `invoices.options.uniqueNumber` with the new name or a way out, and the 0.57 to 0.58 guide has a query that finds duplicate invoice numbers before the migration adds the key.
