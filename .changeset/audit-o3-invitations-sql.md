---
"better-supabase": minor
---

Page the open invitations in SQL. The organizations module adds
`page_organization_invitations(tenant, filters)` next to
`list_organization_invitations`, which stays unchanged, so `upgrade` adds one
function and no table change. `invitationsPage`, `invitationsFacets` and
`invitationsCount` read it, and `OrganizationsOptions` accepts `tenant`, so a
call without `organizationId` reads the request's tenant. An entity page for
`organizations.invitation` now generates its list route and columns.
