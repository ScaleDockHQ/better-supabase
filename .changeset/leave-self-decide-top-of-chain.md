---
"better-supabase": minor
---

The leave block takes `options.selfDecideWhenTopOfChain`. With `approvals: false`, a requester who holds the approve permission and has no manager above them in the employees block may decide their own request through `decide_leave_request`. It is off by default.
