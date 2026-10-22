---
"better-supabase": minor
---

Add the `leases`, `expenses` and `donations` blocks, which post on the ledger instead of keeping balances of their own.

- `leases` (`better-supabase/blocks/leases`) lets units from the assets block to parties, with rent in bigint minor units per week, month, quarter or year. `postDueRent()` posts each rent period on the ledger once, so running it again posts nothing new, and `recordPayment()` settles the balance due. Deposits are held through ledger holds until `terminate()` captures a deduction and returns the rest. Leases renew, and members file maintenance requests on the unit. The `leasesSection` lists a party's leases.
- `expenses` (`better-supabase/blocks/expenses`) collects reports with lines in categories and receipts as attachments on the lines. `submit()` checks the spend policy (a limit per category and a receipt threshold) and opens an approval through the approvals block. An approved report posts on the ledger against the member's payable account, and `reimburse()` settles it.
- `donations` (`better-supabase/blocks/donations`) records gifts and pledges from donors to funds and campaigns, and posts each gift on the ledger. `give()` and `chargeDuePledges()` charge through a `PaymentProvider`, once per pledge period, and `webhook()` applies the provider's events. Gift and yearly tax receipts are numbered per organization, with number-sequences when it's installed, and `givingSummary()` returns a donor's year. The `givingSection` shows a donor's giving.

Install them with `better-supabase add leases`, `add expenses` or `add donations`; each needs `ledger`.
