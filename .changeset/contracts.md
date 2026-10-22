---
"better-supabase": minor
---

Add the `contracts` block (`better-supabase/blocks/contracts`). A contract with a registered counterparty moves from draft through review and e-signature (the contract is frozen as a version and signed with the `signatures` block) to active, expired or terminated. Values are bigint minor units, renewal terms (auto-renew, a notice period) schedule a reminder for the owner before the notice deadline, and `runRenewals()` renews or expires contracts past their end date. Obligations carry due dates and owners, and the `contracts` section lists a record's contracts. Install it with `better-supabase add contracts`; it needs `subjects`, `versions`, `signatures` and `reminders`.
