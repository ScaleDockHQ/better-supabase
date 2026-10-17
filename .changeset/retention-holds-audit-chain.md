---
"better-supabase": minor
---

Retention policies and legal holds in `data-lifecycle`: `createRetention` sets how long each kind of record is kept (`audit`, `outbox`, `webhook_deliveries`, `webhooks`, `inbound_events`, `job_archive`, `usage`, `notifications`, `workflow_runs`), for every tenant, a plan's tenants or one tenant, and places and releases legal holds that every module purge and `purge_organization` (`ORGANIZATION_LEGAL_HOLD`) respect, including chats and trash. Holds emit `legal_hold.placed` and `legal_hold.released`. Without `data-lifecycle`, each purge keeps its `older_than`.

The audit module (version 8) gains `options.chain`, which hash-chains each tenant's entries, and `createAuditChain` in `better-supabase/blocks/audit` verifies the chain and records signed checkpoints of its heads with any `signJwt` signer. Without a `to`, verification runs up to the latest checkpoint, so deleting the newest entries reports a gap. `options.partitioned` creates a new managed log partitioned by month, `better_supabase.maintain_partitions()` adds the months ahead, and `purge_audit_log` drops expired months when no hold or `audit_retention` hook applies. `better-supabase doctor` reports a log that asks for partitions but isn't partitioned (BS335).
