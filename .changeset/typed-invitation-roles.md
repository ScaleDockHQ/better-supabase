---
"better-supabase": minor
---

`InviteRequest`, `Organizations`, `OrganizationsOptions` and `createOrganizations` take the role union as a type parameter (`RoleName` from the generated blocks file, or `RoleNames<typeof config>`), so `invite({ role })` and `onAccept.roles` reject an unknown role at compile time. `InvitationDraft` and `createInvitationsController` take it too. The default stays `string`, and `onAccept.teams` stays `string[]`.
