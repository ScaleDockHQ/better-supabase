# 0923: Page the open invitations in memory

- Status: accepted
- Date: 2026-11-14

## Context

The organizations block reads the open invitations of one organization with `list_organization_invitations`, which the organization overview also calls. The list contract (ADR 0749) needs `page`, `facets` and `count` with declared sorts, filters and search, but the invitation row has no stable keyset and an organization has few open invitations (EX-1329).

## Decision

`invitationsPage`, `invitationsFacets` and `invitationsCount` read the open invitations once and filter, sort and page them in the client. The manifest declares `sorts: [expiresAt, email]`, `filters` and `facets: [role]` and `search: [email]`. The cursor holds the offset of the next row and is valid for the sort and filters it came from. A name the entity does not declare returns `invalid_input` before the read. The example's invitation list gets a resend action beside revoke.

## Alternatives considered

Rewriting `list_organization_invitations` with the list template changed the overview's SQL and every upgraded app's function for a list that rarely passes a page.

## Consequences

The contract works today for the page generator and the example. A SQL list function stays open for an organization with thousands of open invitations; the client methods keep their names when it ships. `tests/blocks/list-surface.test.ts` does not cover this entity, because there is no SQL to compare.
