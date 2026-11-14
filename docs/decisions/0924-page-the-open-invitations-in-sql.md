# 0924: Page the open invitations in SQL

- Status: accepted
- Date: 2026-11-14

## Context

ADR 0923 paged the open invitations in the client because `list_organization_invitations` returns every open invitation and the overview and upgraded apps read it. That left EX-1329 partial: the list contract (ADR 0749) was only half there, and the generated entity page could not read it with a tenant from the request.

## Decision

The organizations SQL module adds `page_organization_invitations(tenant, filters)` beside the old function, which stays as it is. It uses the list template: the `role` filter, `search` over the email, the `expiresAt` (latest first) and `email` sorts, a `role` facet, a count and a keyset cursor. It checks the same `invitations.read` permission and raises `ORGANIZATION_FORBIDDEN` for a caller who may not list them. `invitationsPage`, `invitationsFacets` and `invitationsCount` call it through `entityList`, and `OrganizationsOptions` gains `tenant` so a call without `organizationId` reads the request's tenant (ADR 0939). The `list-surface` test keeps the manifest and the SQL equal.

The example declares `organizations.invitation` as an entity page (`reads: "$blocks.organizations"`), so `gen` writes its list query, `/api/invitations/list` route, columns and navigation entry (ADRs 0859, 0869, 0879).

## Alternatives considered

Rewriting `list_organization_invitations` would have changed the overview's SQL and the function every upgraded app already has.

## Consequences

An upgrade adds one function and no table change. The generated route needs the app's tenant, which `createBlocks` already passes. The client reads the SQL function, so paging no longer holds every invitation in memory.
