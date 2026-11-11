---
"better-supabase": patch
---

With an authorization provider that defines `isApprover`, `approval_eligible_ids` asks it per pending request inside the set query instead of calling `approval_eligible` for every request no set rule matched, so a policy branch such as `id in (select better_supabase.approval_eligible_ids())` no longer re-runs every approver rule per request in every tenant. 2,000 pending requests in ten tenants: 349 ms before, 5.5 ms after. Run `better-supabase upgrade` and generate a migration.
