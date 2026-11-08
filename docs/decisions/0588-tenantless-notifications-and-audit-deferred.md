# 0588: Defer tenantless notifications and audit

## Status

Accepted

## Context

The plan lists a tenantless mode for `notifications` and `audit`, as `ai-chat` has (ADR 0122): a row with no tenant belongs to its user, and a row with one keeps the tenant checks.

## Decision

It does not land in this change. The two modules read the tenant in about 400 places across 23 files (notifications 184, audit 217): the event and recipient tables, the notify function, digests and their schedules, deliveries, tracking tokens, suppressions, the audit entry, the per-tenant retention and hash chain, the restrictive tenant policy of ADR 0099 and the revert and subject helpers. `ai-chat` could make one column nullable because every read already went through its owner. Here the recipient and the tenant are independent: a nullable tenant changes who may read an audit row, how retention and the chain are scoped, and which preferences apply, and each of those is a policy decision that needs its own test fixture. The stage fixtures that would prove it (a tenantless app with notifications and audit) do not exist yet, and `validation-single-tenant` (ADR 0470) holds a B2C app whose modules write no tenant column, but it installs neither block.

The design to start from: `options.tenant: false` on each block, `tenant_id` nullable, the restrictive policy replaced by an owner policy for null rows, one global hash chain for null rows, and retention under a `null` scope. It needs the single-tenant fixture to gain notifications and audit first.

## Consequences

Notifications and audit still need a tenant. An app without tenants has no notifications or audit block today. The item stays open in ADR 0587.
