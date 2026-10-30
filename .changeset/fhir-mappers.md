---
"better-supabase": minor
---

The new `better-supabase/fhir` subpath maps the care blocks to base HL7 FHIR R4 (4.0.1) resources.
`toFhirPatient`, `toFhirRelatedPerson`, `toFhirCarePlan`, `toFhirGoal`, `toFhirObservation`,
`toFhirMedicationRequest`, `toFhirMedicationAdministration` and `toFhirConsent` each turn a block
row into one resource, and `toFhirBundle` wraps them in a `collection`, `searchset`, `transaction`
or `batch` Bundle. `fromFhirObservation` and `fromFhirMedicationRequest` read untrusted FHIR JSON
into an item for `db.observations.ingest` or an order for `db.medications.importOrders`, and
return a `validation` error with every issue instead of throwing. The functions are pure, with
structural types and no FHIR package, and run on every WinterTC runtime. `SPEC_PINS.fhirR4` pins
the version. National profiles are left to a profile layer on top of the base resources.
