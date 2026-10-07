---
"better-supabase": minor
---

An expired invitation now has its own error code. `accept_invitation`, `accept_invitation_by_id` and `update_invitation` (and the matching `organizations` methods) refuse an open invitation past its expiry with the hint `INVITATION_EXPIRED` instead of `INVITATION_INVALID`, which now means unknown, accepted, declined or revoked. The SQLSTATE stays `P0002`. The organizations block exports `InvitationErrorHint`, the union of the invitation codes. Breaking: code that matched `INVITATION_INVALID` to detect an expired invitation must check `INVITATION_EXPIRED`.
