---
"better-supabase": patch
---

- `outbox_register` starts a consumer after the events its own transaction emitted, also while an older transaction is open, so the consumer no longer receives them.
- `sole_owned_organizations` takes an optional `organization` (`soleOwnedOrganizations({ userId, organizationId })`): the list then names at most that organization, and another member's list needs the remove permission only there. The form without it still fails closed. The schema migration drops the one-argument signature (doctor BS235), so move any grant on `sole_owned_organizations(uuid)` to `(uuid, uuid)` in the same migration. In the migrations workflow the drop is skipped when a view or policy still calls the one-argument form, which then stays next to the new one and keeps answering one-argument calls, so drop or recreate those objects first.
- A baseline built before 0.83 does not move restored transaction ids back on `baseline apply`; rebuild it with `baseline build`. Restored rows share one transaction id, so the outbox orders them by position.
- The quotes block declares an `expire` timer (daily at 03:00) that runs `expire()`, so `blockSchedules` schedules quote expiry like the other block timers.
