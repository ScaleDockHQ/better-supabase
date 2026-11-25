---
"better-supabase": patch
---

The state machine's insert check now runs as the invoker and holds only client roles (`anon`, `authenticated`) to the first statuses, so a security definer function a signed-in user calls can insert a record further along again. A machine's `insertStatuses` lists more statuses a client may insert in, and `["*"]` turns the check off. Upgrade note: a client that inserted records past the first step now gets `STATE_TRANSITION_INVALID`; move that insert into a security definer function or the service role, or list the status in `insertStatuses`. Run `better-supabase upgrade`.
