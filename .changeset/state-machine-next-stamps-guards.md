---
"better-supabase": minor
---

The `state-machine` block gains three optional machine settings, and existing machines keep working unchanged.

- `state()` returns `next`, the statuses the caller may move the record to now: the edges from its status, without those whose guard the caller fails, and none while the record is paused. `status_state` returns it as `next`. `gen` also writes each machine's `transitions` to the block's generated options (`blockConfig["state-machine"].options.transitions`), so a UI, API or MCP tool reads the edges without a copy.
- `stamps` sets a column to `now()` when a record enters a status, such as `{ sent: "sent_at" }`, inside the same transition. An insert stamps an empty column, except during an import.
- `guards` checks a transition inside the trigger: `permission` is a key the caller must hold in the record's tenant (`STATE_TRANSITION_FORBIDDEN`, Postgres `42501`; the service role passes), and `check` is a function of the record's row that must return true (`STATE_GUARD_FAILED`, `23514`).
