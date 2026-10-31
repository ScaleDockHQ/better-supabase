# 0157: The psa, ats and intranet presets reuse existing blocks

- Status: accepted
- Date: 2026-10-31

## Context

The block catalog covers the pieces of three common products, but no preset
selects them: professional services automation, applicant tracking and an
intranet. A comparison with HRIS and help desk products showed that `people`
and `helpdesk` already are those presets.

## Decision

Add `psa`, `ats` and `intranet` to `PRESETS` in the `products` group, each as
`saas` plus a list of blocks, with no new block, option or SQL.

- `psa`: contacts, tasks, time-tracking, billable-time, shifts, expenses,
  approvals, quotes, contracts, invoices and numbering, with the shared
  collaboration blocks.
- `ats`: hiring, employees, forms, calendar, bookings, templates, signatures,
  approvals and reminders.
- `intranet`: announcements, knowledge, drive, channels, reactions, employees,
  calendar and acknowledgements.
- HRIS stays `people` and help desk stays `helpdesk`; the presets docs say so.

## Alternatives considered

- Add `hris` and `service-desk` presets too. They would duplicate `people` and
  `helpdesk`.
- Turn on automations by default for `psa` (quote to order). The tenant decides
  how an accepted quote becomes work, so the docs name the switch instead.

## Consequences

- Each preset has a docs page, generated wiring in `tests/validation-presets`
  and a row in the presets index.
- A block's change reaches the presets through the catalog; no preset carries
  its own SQL.
