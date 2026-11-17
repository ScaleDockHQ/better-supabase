---
"better-supabase": minor
---

`blocks.leave.options.decider` names an app function `(request_id uuid) returns boolean` that lets more callers decide a request through `decide_leave_request`, such as every manager up the requester's reporting chain. The database enforces it, and the requester still never decides their own request.
