---
"better-supabase": patch
---

The leave block's `options.selfDecideWhenTopOfChain` now lets a requester with the approve permission decide their own request only when nobody else can decide it. Before, any approver without a manager could approve their own leave, even with other approvers in the organization, and an owner whose manager was offboarded or had no login was refused. Now another active member who holds the approve permission, or an active manager with a login whom the block lets decide (the direct manager under `approver: "manager"`, or anyone up the chain with a `decider`), blocks the self-decision. A custom access model needs `functions.canUser` for this option.

A manager whose employee record has an end date before today no longer decides as the requester's manager, in the direct decide functions of leave, time entries and expenses and in approval routing, just as an offboarded manager doesn't.
