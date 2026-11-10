---
"better-supabase": minor
---

Bank accounts take a `holder` and a `primary` flag. `saveAccount` accepts both, and `BankAccount` returns them. Setting `primary: true` clears the flag on the organization's other accounts in the same currency, so each organization has at most one primary account per currency. Run `better-supabase upgrade` to add the `holder` and `is_primary` columns to `better_supabase.bank_accounts`.
