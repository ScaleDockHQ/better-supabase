---
"better-supabase": minor
---

Add the `medications` block (`better-supabase/blocks/medications`). An organization keeps a medication list, imported from a drug database through a versioned `MedicationCatalog` port (`testMedicationCatalog` in `better-supabase/testing` checks one) or added by hand. Prescribers order a medication for any record with a dose, route and schedule, or as needed with a maximum per day, and `importOrders` brings in a pharmacy's orders by external id. `planAdministrations` plans the doses, members record each one as given, refused or skipped, a high-risk dose needs a second member to check it, and `markMissed` marks late doses missed and notifies the members who manage medications. `chart` reads a record's orders and doses, and the example app adds a `medication-chart` recipe.
