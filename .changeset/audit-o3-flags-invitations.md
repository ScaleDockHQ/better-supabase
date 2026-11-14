---
"better-supabase": minor
---

Enforce an entity's flag key and page the open invitations. An entity that sets
`flag` in `EntitySurface` now lists the `methods` the flag hides, and
`createBlocks({ flags })` returns a `not_found` error from those methods while
the flag is off (`entityFlagHooks` builds the hooks). The organizations client
gets `invitationsPage`, `invitationsFacets` and `invitationsCount` with the
`role` filter, the `expiresAt` and `email` sorts and a search over the email.
