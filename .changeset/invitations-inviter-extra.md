---
"better-supabase": minor
---

Every invitation the invitations module returns now carries what an invitation email needs. `invite_member`, `resend_invitation`, `update_invitation` and `my_invitations` merge in the keys of the app's `invitation_preview_extra` hook (a role label, say), as `invitation_preview` already did, and, when the profiles module is installed, an `inviter` object with the inviter's `id` and public profile fields (`username`, `fullName`, `firstName`, `lastName`, `avatar`). In TypeScript, `Invitation` gains `inviter` (`null` without the profiles module), and `extra` is filled for `invite`, `resendInvitation` and `updateInvitation` too, so an `onInvite` email dispatcher needs no extra reads. Breaking: `Invitation` has a new required `inviter` field, and the hook now also runs for those calls.
