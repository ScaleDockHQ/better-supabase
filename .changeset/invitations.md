---
"better-supabase": minor
---

Invitations can be edited, answered from an in-app inbox and sent for platform roles under the `provider` model. Run `better-supabase sql upgrade`.

- `update_invitation` (`organizations.updateInvitation`) changes an open invitation and emits `invitation.updated`; it refuses an expired one, so call `resend_invitation` first.
- `my_invitations()` lists the signed-in user's open invitations, and `acceptInvitationById` and `declineInvitationById` answer them. Invitations carry `extra` from the `invitation_preview_extra` hook, `createdAt`, `organization` and an `inviter`.
- `options.platformRoles` names the platform role table, with `through`, `canAssign` and `canAssignFor` checked at invite and accept. `through.where` is required when its table is also `roleThrough`'s, and `bs_role_scope` refuses other roles on direct writes (`PLATFORM_ROLE_SCOPE`).
- **Breaking:** accepting or updating an expired invitation fails with the hint `INVITATION_EXPIRED` instead of `INVITATION_INVALID`, which now means unknown, accepted, declined or revoked.
- **Breaking:** `Invitation` has a required `inviter` field (`null` without the profiles module), and the `invitation_preview_extra` hook also runs for invite, resend, update and `my_invitations`.
