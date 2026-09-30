---
'better-supabase': patch
---

Doctor BS405 now measures what PermDock's budget covers. With a `permdock.config.ts`, it warns when `memberships` plus `attrs` from the hook's output pass 1024 bytes (or `doctor.claimsLimit`), measured with `octet_length` as PermDock's hook measures `supabase.hook.budget`. The whole-token check at 2048 bytes is a separate warning, so a normal PermDock token of about 1.5 KB no longer trips it. Without PermDock, `doctor.claimsLimit` still limits the whole token. `memberships_truncated` is reported as before.
