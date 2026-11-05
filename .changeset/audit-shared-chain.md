---
"better-supabase": minor
---

Run the audit log's hash chain on the shared `chain` functions (audit module version 13). `createAuditChain` and its types are removed: call `createChain({ table: "better_supabase.audit_events", tenantColumn: "organization_id", ... })` instead, which also gives you `proof` and evidence bundles. Checkpoints move from `audit_checkpoints` to `chain_checkpoints` on upgrade, existing hashes stay valid, and a verdict no longer has `brokenAt`. `record_chain_checkpoint` now returns the tenant and the signature.
