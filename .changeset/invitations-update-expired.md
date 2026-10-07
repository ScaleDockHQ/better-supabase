---
"better-supabase": patch
---

`update_invitation` and `organizations.updateInvitation()` refuse an expired invitation with `INVITATION_INVALID`, as accept does. Before, an invitation past its expiry but not accepted, declined or revoked could still be edited. Call `resend_invitation` first to renew its expiry, then edit it. Breaking: editing an expired invitation now fails.
