---
"better-supabase": minor
---

Removed `acknowledgePolicy`, `acknowledgements(policyId)`, the `pendingOnly` list option and `policySubjectType` from the compliance client, and `inbox.contacts.upsert` with the `upsert_contact` function from the inbox. Use `db.acknowledgements.acknowledge`, `mine` and `status`, and `contacts.savePerson` with `contacts.addIdentity`. Run `better-supabase upgrade` to drop the function.
