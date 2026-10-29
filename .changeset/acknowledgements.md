---
"better-supabase": minor
---

The new `acknowledgements` block (`better-supabase add acknowledgements`, `better-supabase/blocks/acknowledgements`) records who confirmed they read which version of a record. `assign(organizationId, record, { type, id }, { dueInDays })` asks a user, a team or a role; `mine(organizationId)` lists what the caller still has to read; `acknowledge(record, { versionId, signatureId })` records the caller's acknowledgement of the current version and fails with `ACKNOWLEDGEMENT_VERSION_STALE` when a newer one was published; `status(record)` and `of(record, versionId)` show who acknowledged and who is pending; `notifyDue()` reminds members once their acknowledgement is overdue.

List the record types under `blocks.acknowledgements.on`, each with its `table` and an optional `versionColumn` that holds the record's current version; without it, the current version is the record's latest frozen version in the `versions` block. The block adds the `acknowledgements.read`, `acknowledgements.manage` and `acknowledgements.acknowledge` permission keys (members get `acknowledge`), the events `acknowledgement_assignment.created`, `acknowledgement_assignment.deleted`, `acknowledgement.created` and `acknowledgement.reminded`, and the `acknowledgement-inbox` UI recipe. An app on a permission catalog adds the three keys to its catalog.
