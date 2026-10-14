---
"better-supabase": minor
---

Breaking: `better_supabase.transition()` in the `state-machine` module now runs as the caller instead of as a security definer function. Before, any signed-in user could change the status of any record of a machine, in any tenant. Now the subject table's row level security decides: a caller who can't update the record gets `STATE_SUBJECT_NOT_FOUND` (`P0002`, a `not_found` error from `createStateMachine().transition()`) instead of `true`. Give members an update policy on each machine's table, or call `transition()` with the service role where a server action moved records on their behalf. Approval-gated transitions and `bulk` transitions keep working; a bulk row the caller can't update now fails. The stages timeline only clears and numbers stages within the record's own tenant and machine. Run `better-supabase sql sync` to install module version 2.
