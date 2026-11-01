---
"better-supabase": minor
---

Two more block reads, each one SQL call that runs as the caller. `organizations.overview` returns
the organization, the caller's role, the members with their roles, the open invitations and the
billed seats. `billing.overview` returns the Stripe customer, the seats, the subscription item,
the latest invoices and the usage per meter. `organizations` now lists `billing` and `billing`
lists `usage` as integrations in the catalog.
