---
"better-supabase": minor
---

New `tills` block (`better-supabase/blocks/tills`): till sessions, cash movements, end-of-day counts and bank deposits for a point of sale. The `pos` preset installs it.

- `createTill` and `updateTill` keep cash drawers with a currency and an optional accounting cash account.
- `openSession` starts a shift with an opening float, and a till has one open session at a time.
- `recordMovement` records cash sales, refunds, cash in and cash out. A refund or cash out cannot take more than the drawer holds.
- `closeSession` counts the drawer from denominations or a total and books the variance in accounting.
- `deposit` takes counted cash to the bank, and `reconcileDeposit` matches it to a banking transaction.
- The permission keys are `tills.read`, `tills.write` and `tills.manage`.

Run `better-supabase add tills` and generate a migration.
