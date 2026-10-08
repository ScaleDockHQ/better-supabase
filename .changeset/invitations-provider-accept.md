---
"better-supabase": minor
---

Platform invitations under the `provider` access model check the inviter at accept, not the invitee. A `platformRoles.canAssign` template without `{user}` reads the caller, so at accept it judged the invitee and refused every invitation; it now runs only when the invitation is created, and the new `platformRoles.canAssignFor` (a template with `{user}`) checks the inviter again at accept. The `invitations` module also adds `accept_invitation_by_id(invitation_id)` and `decline_invitation_by_id(invitation_id)` for the invitee's signed-in session, so an in-app inbox can answer invitations without the token, and `createOrganizations` gains `acceptInvitationById` and `declineInvitationById`.
