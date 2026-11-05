---
"better-supabase": minor
---

New `deadlines` block (`better-supabase/blocks/deadlines`): due dates computed from approved, cited rule sets.

- Rule sets belong to the platform, one per jurisdiction and kind. `saveRules` stores a draft version and `approveRules` freezes it with a SHA-256 content hash. With `approvals` installed, approval needs an approved request of the subject type `deadline_rule_version`. An approved version can't change (`DEADLINE_RULE_VERSION_FROZEN`).
- `compute` evaluates a rule against a subject's facts and stores the result as `due` with a date and a citation, or `unknown` with the missing facts named. `recompute` refreshes a subject's open deadlines, and `satisfy` closes one.
- `evaluateRule` and `validateRules` run the same rules in TypeScript, so a preview matches the database.
- Events `deadline.computed` and `deadline.satisfied`. The permission keys are `deadlines.read`, `deadlines.write` and `deadlines.manage`.
- The `filings` preset now includes `deadlines`.

Run `better-supabase add deadlines` and generate a migration.
