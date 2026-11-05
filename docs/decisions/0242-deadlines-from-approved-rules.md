# 0242: Compute deadlines from approved, versioned rule sets

- Status: accepted
- Date: 2026-11-05

## Context

Apps that file notices need due dates that follow a statute: an anchor fact, an
offset, a business-day adjustment and a citation. Hard-coded dates are hard to
audit, and a rule that changes after a deadline was computed must not rewrite
what the user was told.

## Decision

The `deadlines` block keeps rule sets per jurisdiction and kind with no tenant.
A version is a draft until `approve_rule_version` (service role only) freezes
it with a SHA-256 content hash; a trigger refuses later changes with
`DEADLINE_RULE_VERSION_FROZEN`. When `approvals` is installed, approval needs an
approved request of the subject type `deadline_rule_version`.

A rule has an anchor fact, an offset in days, business days or months, an
adjustment and a citation. `compute_deadline` stores one row per tenant,
subject and rule key: `due` with a date, or `unknown` with the missing facts. It
never guesses. The same evaluator exists in SQL and TypeScript, and a test
runs both over the same facts. Apps attach `deadline_fact_trigger` to their own
facts table to recompute, and wire reminders through `blocks.reminders.on`.

## Alternatives considered

- Tenant-owned rules. Tenants would edit statutes, and approval would have no
  single owner.
- A rule language with expressions. Three offset units and three adjustments
  cover the filings in scope, and stay checkable by `validate_deadline_rules`.

## Consequences

Rule sets are readable by every member, but only approved versions. Changing a
rule means a new version; existing deadlines keep the version they used.
