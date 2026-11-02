# 0178: E-prescribing keeps prescriptions in SQL, signed only by their prescriber, and delivers through a port

- Status: accepted
- Date: 2026-11-01

## Context

Medication orders (ADR 0135) record what a patient takes, but an order is not a
prescription: a prescriber signs it, a pharmacy or a national service receives
it, and the signature must not change afterwards. National formats differ per
country, so the library cannot pick one (ADR 0159 sets the same rule for other
ports).

## Decision

`e-prescribing` is a block (`better-supabase/blocks/e-prescribing`) with one
table, `prescriptions`.

- Status is `draft`, `signed`, `sent`, `dispensed` or `cancelled`, moved only by
  security definer functions. Check constraints tie each status to its columns.
- `sign_prescription` needs `e_prescribing.sign` and `auth.uid() = prescriber_id`.
  The service role never signs, so a signature always names a signed-in
  prescriber. Signing freezes the order into `snapshot` and refuses an order that
  is no longer active.
- `PrescriptionGateway` is a versioned port (`apiVersion: 1`), typed structurally
  and bundling no national format. `deliver` gets the prescription and its FHIR R4
  `MedicationRequest` (`toFhirPrescription`) and returns a reference. A gateway
  that throws leaves the prescription `signed` with `delivery_error`, and the call
  is an error with `PRESCRIPTION_DELIVERY_FAILED`, never an exception.
- Cancelling a sent prescription asks the gateway to withdraw it first.
- Every step is an outbox event and an audit entry, and the example's
  prescriptions page lists them with Sign and Cancel.
- The permission keys are `e_prescribing.read`, `.write`, `.sign` and `.manage`.

## Alternatives considered

- Signing with the service role on behalf of a prescriber: rejected, since the
  signature is the legal act and must name a person.
- Storing a reference to the live order instead of a snapshot: rejected, since a
  later dose change would alter a signed prescription.
- Bundling a national format: rejected, since each belongs in its own adapter.

## Consequences

Apps get a signed, auditable prescription flow without choosing a format, and
adapters live in their own packages and test against `testPrescriptionGateway`.
