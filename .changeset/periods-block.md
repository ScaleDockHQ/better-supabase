---
"better-supabase": minor
---

New `periods` block (`better-supabase/blocks/periods`): dated periods per kind with a close protocol that other blocks take part in.

- `createPeriod`, `periodFor`, `isOpen`, `lock`, `close`, `reopen` and `listPeriods` keep ranges with an `open`, `locked` or `closed` status. `periodFor` creates a missing calendar period for kinds that have a cadence.
- A block adds a kind through `contributes.periods` with a blockers function and an on-close function. `close` runs every blocker check first and fails with the `PERIOD_CLOSE_BLOCKED` hint, then runs each closing step in one transaction.
- Accounting contributes `fiscal_period` and leave contributes `leave_year`. The existing `close_accounting_period` and `close_leave_year` keep their names and behavior.
- The permission keys are `periods.read`, `periods.write` and `periods.manage`.

Run `better-supabase add periods` and generate a migration.
