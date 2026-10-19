---
"better-supabase": minor
---

A reference between two app tables scoped to the same tenant (a table that references itself included) now checks the tenant. `sql sync` adds a unique `(tenant, id)` index on the target and a composite foreign key `(tenant, column)`, so a row can no longer point at a row of another organization or workspace; `on delete set null` clears only the referencing column. The pgTAP file checks each composite key.

Migration: run `better-supabase sql sync` and generate a migration. If an existing row already references a row of another tenant, the new foreign key fails to apply; fix or delete those rows first.

Create can link two tables many to many from a table's menu ("Add many-to-many with…"), which adds a junction table with two required references, `on delete cascade` and a unique pair. A Tree primitive adds a table with a `parent_id` that references itself. When you select a table, its edges show the delete action, and a reference that is unique ends in a one-to-one marker.
