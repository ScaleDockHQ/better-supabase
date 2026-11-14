# 0925: Raise the organizations bundle baseline for the invitation list

- Status: accepted
- Date: 2026-11-14

## Context

`invitationsPage`, `invitationsFacets` and `invitationsCount` read `page_organization_invitations` through `entityList` (ADR 0924), the same shared list code the other blocks load (ADR 0750). `./blocks/organizations` grew from 55410 to 61575 bytes gzip and `./blocks/saas`, which includes it, from 126590 to 134132.

## Decision

Raise both baselines to the CI-measured sizes. The code is the shared list contract, not new logic, and a block that uses it once pays for it once.

## Consequences

Apps that import `better-supabase/blocks/organizations` ship about 6 KB more gzip. A later change that splits the CSV export out of `entityList` can lower the baseline again.
