---
"better-supabase": patch
---

A block runs over a view of yours again, as `ownership: "adopt"` did in 0.14. When your schema files or the snapshot create a view or materialized view at a block table's name (its default name, or the one `blocks.<name>.tables` maps), the block writes no table DDL for it: no `create table`, added columns, constraints, indexes, row level security, grants or policies. It still writes the functions that read the view. An optional column the view lacks counts as mapped to `null`, and a required one stops `upgrade` with an error that names the view and the column. A view at the name of a table only the block keeps is still an error. Doctor reports a block whose API writes through a view Postgres can't update (BS349). `organization_member_role` now leaves out disabled memberships, like the other membership checks. `better-supabase/sql` exports `declaredViews` and `adoptedViews`.
