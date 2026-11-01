# 0197: Shared engines for recurrence, periods, money and digests are planned, not shipped

- Status: proposed
- Date: 2026-11-01

## Context

The seeds and business engines plan names five shared engines: an RFC 5545
recurrence expander on Temporal (`rrule_occurrences` in SQL), period and
lifecycle helpers, money and digest helpers with consent checks, vertical glue
between blocks, and Postgres features (pg_cron schedules and similar).

## Decision

None of the five engines ships with the seeds change (ADR 0196). Each is a
public API and needs its own docs page, example, exports entry and baselines
(architecture invariant 9), and a half-built engine without a consumer would
fail Knip. They move to their own changes, in this order: recurrence, periods
and lifecycle, money and digest, vertical glue, Postgres features.

## Alternatives considered

Shipping an unexported expander with tests: no consumer, so Knip rejects it and
it would rot.

## Consequences

Maintenance plans, appointments and calendar alarms keep their own recurrence
handling until the shared expander exists. Revisit when a second block needs
the same rule.

## Deferred: vertical glue (engine-glue)

The glue change ships the helpers that chain existing part clients and need no
new SQL: `crm.route`, `crm.attainment`, `saas.rotateApiKey`, `support.escalate`,
`commerce.processReturn`, `projects.utilization`, `projects.financials` and
`projects.retainerDrawdown`. Each has a test with fake parts, a docs section and
a server action in the Next.js example. `saas.rotateApiKey` also has the
standalone `createKeyRotator`, because the example does not install the billing
part of `saas`.

These stay planned, because each needs a SQL function, a migration and a
golden file of its own, which is a larger change than a typed chain:

- `crm`: `renewalsDue` (contract renewals become deals), `contacts.duplicates`
  with `pg_trgm`, and the NPS detractor to task chain (`tasks` is not a part of
  `crm`).
- `saas`: `cloneOrganization` (needs the access matrix table list in SQL),
  `subjectAccessRequest` on the queue, `brandTenant` and the plan change
  fan-out to flags.
- `support`: `proposeArticle` (the `knowledge` client has no draft call to
  chain) and the major-incident bridge.
- `commerce`: `available_to_promise`, loyalty points on the ledger, and the
  abandoned-cart timer to sequences.
- `finance`: `cashForecast`, intercompany pairs and `trustReconcile`. A forecast
  needs due dates per open invoice, which `invoices.aging` does not return.
- `projects`: milestone billing automation.
- `people` and `recruiting`: the requisition budget check, `offer` (no template
  or signature part in `recruiting`) and the interview intersection with
  `tstzmultirange`.
- `scheduling`: waitlist auto-promotion and `passes.freeze` (`passes` is not a
  part of `scheduling`).
- `care`, `cms`, `property`: `claimPeriod`, `cms.calendar` and `leases.rentRun`
  with late fees.

`projects.utilization` counts the whole week in TypeScript from
`timeTracking.list`. A SQL rollup would scale better for large teams and should
replace it when a metrics rollup for time entries exists.
