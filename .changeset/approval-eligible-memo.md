---
"better-supabase": patch
---

The approvals module (version 4) reads the caller's permission, role, team and manager approvals
once per statement through the new `approval_fact`, kept with `memo_get` and `memo_set` under the
statement start and a generation that statement triggers on memberships, team members and employees
move. The request's status, step and decisions stay live per row. `approval_eligible` gains an
`approval_eligible(approval_requests)` overload, so `approval_eligible_ids`, `my_work` and app
policies pass the row instead of fetching it again. A list of 1,000 pending requests now runs one
`can()` call instead of 500, and `approval_eligible_ids()` drops from about 150 ms to about 10 ms
on the local stack. Run `better-supabase upgrade`, then `add --adopt` for the block row.
