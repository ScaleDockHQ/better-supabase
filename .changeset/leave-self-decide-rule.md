---
"better-supabase": patch
---

The leave block's `options.selfDecideWhenTopOfChain` now lets a requester with the approve permission decide their own request only when nobody else can decide it. Before, any approver without a manager could approve their own leave, even with other approvers in the organization, and an owner whose manager was offboarded or had no login was refused. Now another active member who holds the approve permission, or an active manager with a login whom the block lets decide (the direct manager under `approver: "manager"`, or anyone up the chain with a `decider`), blocks the self-decision. A custom access model needs `functions.canUser` for this option.
