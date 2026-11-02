---
"better-supabase": minor
---

Add the `commissions` and `referrals` blocks. Commissions keeps plans (flat or
marginal tiers) per seller, accrues commissions on the ledger from sold records
or, with the `invoices` option, from paid invoices, builds statements per period
and pays them out, and exposes `commission_payroll_lines` for payroll. It
contributes a `commission_period` kind to the periods block. Referrals keeps
codes per member, attributes signups (and accepted invitations with the
`invitations` option) and posts a reward once to the ledger when a referral
qualifies.
