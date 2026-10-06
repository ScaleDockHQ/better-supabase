---
"better-supabase": minor
---

`orderBy` sorts by a column of a to-one relation: `orderBy: { organization: { name: "asc" } }`. Over PostgREST the root query sends `order=<alias>(name).asc`, reusing the relation's include or adding an empty embed for it; the SQL executor sorts by a scalar subquery. It works in `findMany`, `findFirst` and offset `paginate`. To-many relations, a second level, sorts inside an include, cursor pages, aggregates and SQLite return `invalid_request` or `unsupported`. Include and aggregate `orderBy` are now typed as `ColumnOrderByArg`, the table's own columns, which is what they accepted before.
