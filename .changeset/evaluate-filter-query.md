---
"better-supabase": minor
---

`evaluateFilterQuery(query, record, fields, clock)` from `better-supabase/list` tests a `FilterQuery` tree on one record in memory, with the same operators, case rules, relative dates and null handling as `filterWhere` compiles to SQL. It returns `matched` and the result of every rule and group by node id (`null` when a comparison met a missing value). A field's `column` may be dotted to read a nested value, and `FilterRecordField` describes fields that aren't table columns.
