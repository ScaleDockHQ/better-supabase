---
"better-supabase": minor
---

New `e-prescribing` block (`better-supabase/blocks/e-prescribing`): prescriptions of medication orders with the states draft, signed, sent, dispensed and cancelled, signed only by their prescriber, and delivered through the versioned `PrescriptionGateway` port. `toFhirPrescription` in `better-supabase/fhir` builds the `MedicationRequest`, and `testPrescriptionGateway` in `better-supabase/testing` checks a gateway. Run `better-supabase upgrade` to add the `prescriptions` table and its `e_prescribing.*` permissions.
