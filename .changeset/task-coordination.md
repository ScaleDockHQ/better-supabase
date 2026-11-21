---
"better-supabase": minor
---

Add task coordination for queues that people and agents share. `tasks` gains prerequisites (`options.needs`, `setNeeds`, the `ready` filter and `task.unblocked`), `createPlan`, leased claims (`claim`, `claimNext`, `renew`, `release`, `delegate`), holds, `note` on `complete` and `cancel`, `fail`, `move` and `moveMany`, `stageTimes` and the realtime topic `tasks:{organizationId}`. `db.permissions.explain` and `explainPermissionTool` say why a member holds or lacks a key.

Upgrade notes:

- The tasks module is at version 6. Run `better-supabase db diff` and apply the migration. New columns (`waiting_on`, `held_at`, `hold_kind`, `close_note` and the claims table) exist on an adopted table only when you map them; the claims table needs `app: {}` when you set `ownTablePolicies: "app"`.
- Audit rows and timeline entries label an `act` of kind `agent` as `agent`. They were `impersonation` before, so reports that group by actor kind change.
- `setNeeds` and `create({ needs })` need the relations manage permission.
- `fail` needs a canceled stage; with `canceled: null` it raises `TASK_OUTCOME_UNAVAILABLE`.
- The client method is `createPlan`; `createMany` stays retired.
- A new function `better_supabase.explain_permission` is granted to `authenticated`.
