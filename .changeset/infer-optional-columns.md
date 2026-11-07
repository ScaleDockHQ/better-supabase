---
"better-supabase": minor
---

A `columns.<table>.<column>: null` entry for an optional column the view you map a block over lacks anyway is now an error that names the entry, since the block already leaves that column out. A `columns.<table>.tenant` entry that repeats `sql.tenantColumn` is an error too. `add --adopt` no longer proposes the null entries for a view. Remove the entries the message names; a `null` entry for a column your view has, or for a table you own, still works.
