# 0197: Shared engines for recurrence, periods, money and digests are planned, not shipped

- Status: superseded by 0719
- Date: 2026-11-01

## Context

The seeds and business engines plan names five shared engines: an RFC 5545
recurrence expander on Temporal (`rrule_occurrences` in SQL), period and
lifecycle helpers, money and digest helpers with consent checks, vertical glue
between blocks, and Postgres features (pg_cron schedules and similar).

## Decision

None of the five engines ships with the seeds change (ADR 0205). Each is a
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

## Periods engine (feat/engine-periods)

The `periods` block ships with this change: the `periods` table, `period_for`,
`period_is_open`, `lock_period`, `close_period`, `reopen_period` and the close
protocol where a block contributes `blockers` and `onClose` functions through
`contributes.periods`. Accounting contributes `fiscal_period` and leave
contributes `leave_year`. The existing `close_accounting_period` and
`close_leave_year` keep their names.

### Deferred

- Payroll runs, usage billing windows and forecast snapshots do not contribute a
  kind yet. Each needs a range to row mapping of its own, and none of them has a
  second consumer to shape it. They add a kind with `contributes.periods`.
- `finance.closeMonth` and `leave.rolloverYear` did not exist, so nothing
  converts to a wrapper. Closing a fiscal period or a leave year stays on
  `closeAccountingPeriod` and `closeYear`, and `periods.close` calls the same SQL.
- Blocks do not check `period_is_open` before they write. Accounting still
  refuses posts into closed fiscal periods by its own status, and leave has no
  write guard for a closed year. Adding the guard per block is the follow-up.

## Lifecycle engine (feat/engine-periods)

Shipped: the SLA escalation ladder. `sla_policies.escalations` holds steps of `at` (share of the
clock's time), `action` (`notify`, `reassign`, `page`) and a `target`. `check_sla_clocks` fires
each step once per clock, records it in `sla_escalations` and emits `sla.escalated`. A binding's
`owner` column is what `reassign` writes.

### Deferred

- The `@bsb lifecycle` table tag for status, transitions and history. The existing `lifecycle`
  table feature is about retention, so the tag needs its own name and parser work in
  `src/cli/gen/table-tags.ts` and `src/sql/table-features.ts`.
- A `late` flag on state machine contributions. The `bsb_transition_<name>` trigger can't be
  created from the state machine's build on tables of later modules (contracts 125, dispatch
  123), so contracts and dispatch can't contribute machines until the trigger is created from
  the contributing module.
- Cases, inbox, tasks and orders transitions. Cases set their status from another trigger, and
  the `UPDATE OF` transition trigger doesn't fire for it.
- SLA clock start and stop per state from the tag. Bindings (`on.<type>.pause` and `resolve`)
  keep doing this.

## Shipped: recurrence and maintenance

The recurrence engine and the maintenance engine shipped on `feat/engine-maintenance`.

- Recurrence: `better-supabase/recurrence` (`expandRule`, `rruleOccurrences`) and the
  `recurrence` SQL module (`rrule_occurrences`, `rrule_next`). Calendar, tasks, reminders and
  templates expand through it, `calendar_rule_starts` wraps the SQL function, and a
  conformance test compares the TypeScript and SQL instants.
- Maintenance: the `housekeeping` SQL module (`maintenance()`, `maintenance_jobs`,
  `maintenance_schedule()`, `maintenance_scheduler()`) and a `housekeeping` contribution that
  `approvals`, `trash`, `webhook-inbox`, `rate-limit`, `idempotency` and `chat-sdk-state`
  use. The old purge and expire functions keep their names.

### Deferred (recurrence and maintenance)

- Recurrence: bookings series, shifts and maintenance plans keep their own date arithmetic.
  Maintenance plans use `everyDays` intervals rather than RRULE, so they move only when plans
  take a calendar rule. The templates SQL function `due_template_occurrences` exists, but the
  TypeScript client still expands schedules itself and skips unreadable rules, while
  `rruleOccurrences` treats an unreadable rule as one occurrence. Moving the client onto the
  SQL function needs that difference decided first.
- Maintenance: the fallback that runs `maintenance()` from the `block_ticks` queue when pg_cron
  is missing is not wired. Without pg_cron the app calls `maintenance()` from a cron route.
  There is no doctor finding yet for "jobs are due and no scheduler runs"; it needs a live
  database check, which doctor only makes for the advisors. The other modules with purge
  functions (`audit-retention`, `queue` archive, `workflow-sdk`, `support`, `usage-kinds`,
  `webhooks-out`, `notifications-delivery`) still need their own schedule.
- Docs examples: both engines have a docs page with an inline example. A runnable app under
  `apps/examples` is not added.

## Audit of seeds and engines (feat/seeds-and-engines-2)

The five engine branches were merged into the seeds branch and reached `main` through the
composition PR. This change adds the issue check the seeds change left open: `checkProject` reports
`unknown_seed_block` and `unknown_seed_variant` (source `seeds`) for a design whose `seeds.variants`
names a block or variant the catalog doesn't offer.

### Still deferred

- Preset seed variants (`NamedPreset.seeds`) wait for a block that declares a variant. No block does
  yet, so a preset default would fail the check above.
- Module defaults that don't fit a declared table: inbox statuses are a check constraint, not rows;
  pipelines are created per subject type and scope on first use; the accounting chart depends on
  `setup_accounting` settings; permission roles are `permissions` overrides, not a catalog table.
  Each needs a design of its own and a migration through the native stack.
- Composite glue seeds and the format 9 docs page wait for the first composite with defaults.

## Shipped in feat/seeds-defaults-and-money-engines

- Seeds: defaults for pipelines, accounting charts (`generic`, `nl-rgs`), permission catalog roles,
  inbox statuses, attachments document types, calendar holiday sets, cases, leave, risks and tax
  codes; preset variants; the `seeds` umbrella called from `create_organization`; doctor findings
  for declared defaults that are not installed.
- Money and engines: `commissions` and `referrals` blocks, notification digests (a housekeeping
  job), the `requires_consent` gate, revenue recognition schedules in accounting, native
  subscriptions with proration in billing, and the remaining maintenance and glue wiring.

### Still deferred

- Moving the templates TypeScript client onto the SQL occurrence function, and a doctor finding for
  "jobs are due and no scheduler runs" (needs a live database check).
- Schedules for the purge functions of `audit-retention`, `queue` archive, `workflow-sdk`,
  `support`, `usage-kinds`, `webhooks-out` and `notifications-delivery`.
- An example app per new engine under `apps/examples`.
