---
"better-supabase": minor
---

Adopt mode takes enum columns where a block writes kinds and subject types. In adopt mode the tags block casts the `kind` and `subjectType` values it writes and compares, and `next_number` casts the `entity`, to the adopted column's type through the new `better_supabase.as_column_type(value, target)`, so `kind public.organization_tag_kind` or `entity public.workflow_subject_type` works. An enum on any other text column a block writes a parameter or computed value into is refused instead of failing at runtime (columns a block writes only string literals into, such as the teams `status`, may stay enums): `sql sync` and `better-supabase adopt` report it when the schema files declare the enum, and doctor reports it as BS342. A module table spec lists its castable columns in `typed`, and `ModuleContext.cast(table, column, value)` renders the cast.
