---
"better-supabase": minor
---

New `clinical-decision-support` block (`better-supabase/blocks/clinical-decision-support`): alerts over a record's medication orders, with a versioned port for external engines.

- `saveRule` keeps built-in rules: dose range, duplicate therapy and interaction.
- `evaluate` runs the built-in rules, then each engine passed as `engines` (a `ClinicalDecisionSupport` with `apiVersion: 1`), and stores the alerts.
- `alerts` lists open alerts, and `decide` acknowledges or overrides one with a reason. Every raise and decision is an event and an audit entry.
- `testClinicalDecisionSupport` in `better-supabase/testing` checks an engine.
- The permission keys are `clinical_decision_support.read`, `clinical_decision_support.write` and `clinical_decision_support.manage`.

Run `better-supabase add clinical-decision-support` and generate a migration.
