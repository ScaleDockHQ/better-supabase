# 0173: Clinical decision support evaluates rules over medication orders and keeps the port open

- Status: accepted
- Date: 2026-11-01

## Context

The care blocks (ADR 0135) record medications, observations, care plans and
consents, but nothing warned a prescriber or nurse about a dose outside its range,
the same therapy ordered twice, or two medications that interact. Hospitals and
pharmacies already run decision support engines, so the library must not hard-code
one.

## Decision

`clinical-decision-support` is a block (`better-supabase/blocks/clinical-decision-support`)
with two tables, `care_rules` and `care_alerts`.

- A small built-in rule set lives in SQL: `dose_range` (one medication with a
  minimum, a maximum and a maximum per day), `duplicate_therapy` (two or more
  medications of one therapy group) and `interaction` (two medications).
  `evaluate_care_rules` checks the active medication orders of a record and
  raises, updates and resolves alerts, keyed by a stable fingerprint.
- `ClinicalDecisionSupport` is a versioned port (`apiVersion: 1`), typed
  structurally and bundling no engine. `care_decision_context` returns the care
  plans, observations, medications and consents of a record, the engine answers
  with alerts (interaction, allergy, dose range or other), and `record_care_alerts`
  stores them under the engine's key. Alerts an engine no longer returns resolve.
  The key `built-in` is reserved. An engine that throws gives a `CARE_ENGINE_FAILED`
  error and never an exception.
- An alert is acknowledged or overridden through `decide_care_alert`; an override
  needs a reason. A decision survives re-evaluation of the same fingerprint.
- Every raise, decision and resolution is an outbox event and an audit entry, and
  the example's care alerts page lists them.
- The permission keys are `clinical_decision_support.read`, `.write` and `.manage`
  (rules).

## Alternatives considered

- Bundling an interaction database: rejected, since licences and clinical content
  belong to the engine.
- Blocking an order on a critical alert: rejected, since the prescriber decides;
  the override and its reason are the record.

## Consequences

Apps get alerts without choosing an engine, and an engine in its own package plugs
in through the port and the `testClinicalDecisionSupport` conformance kit. The
built-in rules know medication ids only, not codes or substances.
