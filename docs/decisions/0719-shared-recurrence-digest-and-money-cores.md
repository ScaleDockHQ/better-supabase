# 0719: Bookings share the recurrence core, and digests and money formatting get one helper each

- Status: accepted; supersedes 0197
- Date: 2026-11-12

## Context

ADR 0197 recorded five shared engines as planned and listed the recurrence
expander, the digest helper and the money helpers as missing. Since then the
recurrence expander shipped at `better-supabase/recurrence`, the money type and
its minor-unit codec shipped (`better-supabase/commerce` and `blocks/money-codec.ts`),
and notifications digests shipped. The block consistency audit (EX-1290, EX-1291,
EX-1293, EX-1315, EX-1316) found what is still unshared:

- Bookings read and write RRULE text with their own parser in `series.ts`, and
  `booking_series_starts` expanded a series with its own date loop in SQL, so a
  series and a calendar event could differ across a daylight saving change.
- The digest loop (claim, send, record) lives only in `notifications/digests.ts`.
- The example's block list formats money per page, with no column kind for it.
- ADR 0064 names `better-supabase/flows` and `defineFlow`, which never shipped.

Maintenance plans of kind `rrule` already call `rrule_occurrences` through
`maintenance_next_occurrence` and the block requires the `recurrence` module.

## Decision

Recurrence. `better-supabase/recurrence` exports `parseRrule` and `formatRrule`
with the `RecurrenceRule` type, built on the parser `expandRule` uses.
`parseRecurrence` and `formatRecurrence` in the bookings block call them and keep
the daily and weekly subset. `booking_series_starts` keeps its name, arguments and
validation (BOOKING_RULE_INVALID) and expands through
`better_supabase.rrule_occurrences`; the `bookings` module requires `recurrence`.
A migration replaces the function (slot 20261204). A `time` maintenance plan
stays an interval from the last completion, because it is not a calendar rule.

Digests. `runDigests` and `digestLines` in `src/blocks/digest.ts` hold the claim,
send and record loop. Notifications calls it; the next block with held digests
passes its own three functions. It is internal to the blocks, not a subpath, so
it needs no export entry.

Money. The money type, the codec and `formatMoney` already are the shared
helpers, so nothing new is extracted. The example's block list gets a `money`
column kind that reads `MoneyJson` and formats it with `formatMoney` in the
page's locale.

Flows. No `flows` subpath ships. ADR 0064 stays superseded by 0093, and the
roadmap no longer lists `defineFlow`. No docs page or skill names it.

Periods and lifecycle ship as the `periods` block. This ADR replaces 0197 as the
record of what is shared; 0197 is marked superseded.

## Alternatives considered

Moving `time` maintenance plans onto a rule with `FREQ=DAILY;INTERVAL=n`: it
fires on a fixed calendar, not `n` days after completion, so finishing work late
would change the due dates. Rejected.

A public `better-supabase/digests` subpath: only one block uses it, and a public
API needs a docs page and an example (invariant 9). Revisit when an app needs it.

Shipping flows: ADR 0093 replaced the plan with named instances and sections, and
no consumer asks for it.

## Consequences

A series in bookings expands exactly like a calendar event. The bookings entry
grows about 4 KB gzip, because it now includes the expander; the recurrence entry
grows 0.6 KB for the parser. The pgTAP suite checks that a series keeps its local
time across a daylight saving change.

The server chunk of every `(app)` route grows about 0.9 KB raw (the rule parser and
writer, and the digest helper), past the 512 B slack. `tests/next-build/server-baseline.json`
is re-measured for the grown routes by removing them and running the update, as ADR 0688
did. The first-load baseline does not move: the `money` column formats on the server
(`withMoneyCells`), because importing `formatMoney` into the client list view added
about 3.5 KB raw to 76 routes.
