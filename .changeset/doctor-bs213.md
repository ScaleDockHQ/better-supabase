---
"better-supabase": minor
---

Doctor BS213 warns when `anon` or `authenticated` may insert or update a column that RLS helpers read to decide access, such as `memberships.role` or `contacts.customer_id`, and a policy lets them write the row. It also checks the `decidingColumns` in PermDock's manifest and names PD028. The finding lists the revoke and the grant of the remaining columns. Snapshots now record column-level insert and update grants (`columnGrants`); older snapshots only show table grants.
