# 1009: Close the commerce and finance findings of lane X8

- Status: accepted
- Date: 2026-11-14

## Context

Eight example findings in commerce and finance were deferred because a screen or
a read function was missing: the instruments that may take a laboratory result
(EX-1106), a list of revenue recognition schedules (EX-701), request lines that
name a variant (EX-1112), stock allocations and pick lists (EX-1110), goods
receipts for putaway (EX-1111) and a bank statement behind a cash deposit
(EX-1113). Guest checkout in the public store (EX-818) needs Auth settings.

## Decision

Two read functions join the library, both behind the block's read permission and
both stable and tenant scoped:

- `list_qualified_instruments(tenant, on_date)` in the lims module returns the
  asset ids that hold `options.instrumentQualification` on a day, and an empty
  list without the option. The block client exposes it as
  `lims.listQualifiedInstruments`. The result form reads one list instead of
  calling `instrument_status` per asset.
- `list_revenue_recognition_schedules(tenant, limit_count)` in the accounting
  module (with `options.recognition`) returns every schedule with its row count
  and its recognized amount, so a recurring list needs no hand-written policy.

The example gains the screens: a variant select on request lines, dialogs for
allocations and pick lists, goods receipts with putaway suggestions and a
receive-order dialog, and an MT940 import plus a match dialog on the deposits tab.
No new migration touches a table, and the one migration adds a function.

EX-805 is closed: the public store, the inventory ledger and the deepened pages
exist, and what stays open is tracked by its own row (EX-818).

## Consequences

`security-definer-functions` for lims grows from 66 to 72 in the practices
baseline, because the golden renders the module in six variants. EX-818 stays
deferred until a maintainer turns on anonymous sign-ins (with a captcha) in every
Supabase project and the orders block's checkout is checked for a non-member.
