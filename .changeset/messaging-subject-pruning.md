---
"better-supabase": minor
---

Messaging reads prune record conversations by the record table's own visible rows before the per-row `can_subject` check.

- Messaging: a commented subject type whose `permissions.read` names the provider's `rows` renders `subject_id in (select s.<id>::text from <subject table> s)` in the follows branch instead of letting every row reach `can_subject`. The set is a superset of the rows `can_subject` can pass, because `can_subject` already requires the record row to be visible under the same policy, so visibility does not change. It runs once per statement as a hashed subplan, so a conversation in another tenant no longer calls the provider's row function once per row. A commented type without `rows` keeps `true`.
- Subjects and permissions: `can_subject` and `can` carry `cost 1000`, so the planner keeps the set check ahead of them.

Run `better-supabase upgrade` to rewrite the messaging module's policies and functions.
