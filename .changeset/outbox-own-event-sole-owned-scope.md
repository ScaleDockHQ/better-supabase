---
"better-supabase": patch
---

- `outbox_register` starts a consumer after the events its own transaction emitted, also while an older transaction is open, so the consumer no longer receives them.
- `sole_owned_organizations` takes an optional `organization` (`soleOwnedOrganizations({ userId, organizationId })`): the list then names at most that organization, and another member's list needs the remove permission only there. The form without it still fails closed.
- A baseline built before 0.83 does not move restored transaction ids back on `baseline apply`; rebuild it with `baseline build`. Restored rows share one transaction id, so the outbox orders them by position.
