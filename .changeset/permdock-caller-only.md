---
"better-supabase": patch
---

Under the `permdock` access model, `can_user()` and `member_can()` raise SQLSTATE `0A000` (hint `ACCESS_CALLER_ONLY`) for anyone but the caller instead of returning `null`, because PermDock's helpers read `auth.uid()`. The invitations module no longer re-checks the inviter's permission when an invitation is accepted, and the notifications module no longer filters recipients by their read permission, under that model; in 0.5.0 the re-check passed silently on the `null` answer, and the filter dropped every recipient but the sender. Check both in the app when they matter. Run `better-supabase sql add` to rewrite the installed files.
