---
"better-supabase": minor
---

`previewInvitation(token)` returns the keys an `invitation_preview_extra` hook adds, such as a role label or branding, as `extra` on `InvitationPreview`. Before, the TypeScript side kept only the fixed preview fields, so those keys never reached the app.
