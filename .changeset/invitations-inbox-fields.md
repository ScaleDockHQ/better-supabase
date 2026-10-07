---
"better-supabase": minor
---

`my_invitations()` returns each invitation's `created_at`, its `organization` (the id plus `previewColumns`) and the keys of an `invitation_preview_extra` hook, so an in-app inbox no longer reads the invitations table itself. The TypeScript `Invitation` gains `createdAt`, `organization` and `extra`; `invite` and `resendInvitation` return `createdAt` and `organization` too.
