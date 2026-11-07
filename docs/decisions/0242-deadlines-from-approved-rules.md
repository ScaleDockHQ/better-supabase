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

## Amendment (2026-11)

A rule set version is a whole: ordered groups, ordered rules with three-valued
conditions, exceptions and a deadline grammar (single count, `first_of`,
`earlier_of`, `later_of`, `before`, monthly periods), a counting block with
authored holidays, and opaque `meta` per rule, group and version, frozen under
one hash. The evaluator returns one result per group (per month for a periodic
rule) in eight kinds: due, unknown, pending, undated, not_covered,
not_applicable, not_required, barred. Facts are three-valued: absent is
unknown, null is "does not exist or has not happened", a value is an answer.
Parts marked draft or review_required are carried for display and never
decide. The block never reads `meta`; the adopter keeps document data there so
date and duty come from one approved artifact. The v1 shape (anchor, offset) is
converted by the module's upgrade step; approved versions keep their old hash
in `meta.previous_content_hash`.

Rejected: an expression language (the grammar above is the closed set the
fifty-state bundle uses); per-group compute (the barred cascade crosses
groups); a shared holiday table (statutory holiday lists differ per
jurisdiction and must freeze with the version).
