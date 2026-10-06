---
"better-supabase": minor
---

New SaaS blocks, each an SQL module with a subpath: `better-supabase/blocks/api-keys`, `blocks/audit`, `blocks/settings`, `blocks/usage`, `blocks/billing`, `blocks/flags`, `blocks/comments`, `blocks/attachments`, `blocks/data-lifecycle`, `blocks/sso`, `blocks/onboarding` (with `blocks/onboarding/react`), `blocks/waitlist` and `blocks/announcements` (with `blocks/announcements/react`). Add the module with `better-supabase sql add <name>`; each block's page under `/docs/blocks` shows the setup. `stripe` is an optional peer that only the billing and usage blocks load.

The audit block lists entries with `auditListQuery`, exports a tenant's log as NDJSON or OCSF with `exportAuditLog` and `toOcsf`, and sets retention per tenant with `setAuditRetention`. The flags block evaluates the same rollouts in SQL (`flag_enabled`) and in an OpenFeature-shaped provider. The SSO block serves SCIM 2.0. `SPEC_PINS` gains `ocsf`, `openfeature` and `scim`.

New event types: `organization.domain_verified`, `organization.deletion_requested`, `organization.deletion_cancelled`, `organization.purged`, `billing.*`, `comment.created`, `comment.mentioned`, `comment.deleted`, `attachment.uploaded`, `attachment.scanned`, `data_export.requested`, `data_export.ready`, `data_export.failed` and `waitlist.approved`.

Breaking changes:

- The server's `auth.kind` gains `"apiKey"` for callers that `apiKeyResolver` accepts. An exhaustive `switch` over `auth.kind` needs the new case.
- `DbError` gains the `quota_exceeded` kind (HTTP 429), raised by `consume_quota`. An exhaustive `switch` over `DbError["kind"]` needs the new case.
- `purgeAuditLog` moves from `better-supabase/blocks/jobs` to `better-supabase/blocks/audit`. Change the import.
