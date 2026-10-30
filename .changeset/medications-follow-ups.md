---
"better-supabase": minor
---

Medications gain signatures, extra columns and guest reads. `approveOrder` approves an order with
the prescriber's completed signature, and `recordAdministration` takes a `signatureId`. The new
`medicationExtraColumns` and `administrationExtraColumns` options add columns to the catalog and
dose tables (`fields` on `saveMedication` and `recordAdministration`). `guestRead: true` lets a
guest with a read grant read a record's orders, doses and medications. `record_medication_administration`
has a new signature, so apply the new migration with `better-supabase upgrade` and regenerate your
bindings.
