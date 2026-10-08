---
"better-supabase": minor
---

The `provider` access model answers for other users through the authorization provider's `idsWithFor`, `isPlatformFor` and `canAssignFor` templates. With them, `can_user()` and `member_can()` answer for any user, the invitations module checks the inviter's permission and role assignment again at accept, and the notifications module filters recipients by their read permission. The access docs list which module checks change under the provider model.
