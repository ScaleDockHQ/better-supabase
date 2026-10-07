---
"better-supabase": minor
---

The invitations module adds `update_invitation(invitation_id, invitee_email, invitee_role, prefill)`, which changes an open invitation's email, role or prefill with the checks `invite_member` makes (the invite permission, the role ceiling for the current and the new role, an address that is already a member). The token and expiry stay, and it emits `invitation.updated`. In TypeScript, `organizations.updateInvitation(id, { email, role, prefill })` calls it, so apps no longer need a client update policy on the invitations table.
