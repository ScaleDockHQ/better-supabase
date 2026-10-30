---
"better-supabase": patch
---

A compliance policy that requires acknowledgement now reaches every member, owners and admins
included. It is assigned to the new every-member principal (a `role` assignment with the id `*`)
instead of the `member` role. `assign_acknowledgement` and `db.acknowledgements.assign` accept
`{ type: "role", id: "*" }`, and the data step moves existing policy assignments of the `member`
role onto it. Run `better-supabase add --adopt` after upgrading.
