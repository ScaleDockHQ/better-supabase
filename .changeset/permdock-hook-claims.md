---
'better-supabase': patch
---

The PermDock guide lists every claim PermDock's generated hook writes (`user_role`, `roles`, `memberships`, the tenant claim, `attrs`, `authz_ver` and `memberships_truncated`). The migration guide and the `sb.userMetadata()` TSDoc say that `session.profile` is for display only, and that roles, memberships, the tenant and entitlements never come from it.
