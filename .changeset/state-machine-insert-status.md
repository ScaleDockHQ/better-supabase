---
"better-supabase": patch
---

A state machine refuses a new record in a status the initial status can't reach in one step (`STATE_TRANSITION_INVALID`), unless the insert runs in an import or as the service role. Before, a client with insert access could create a quote that was already accepted. Run `better-supabase upgrade` to regenerate the state-machine module.
