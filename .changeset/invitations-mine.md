---
"better-supabase": minor
---

The `invitations` module adds `my_invitations()`: the open tenant and platform invitations for the signed-in user's confirmed email, without their tokens, for an in-app inbox that then answers them with `accept_invitation_by_id` and `decline_invitation_by_id`. `createOrganizations` gains `myInvitations()`.
