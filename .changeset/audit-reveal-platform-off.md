---
"better-supabase": patch
---

Without `permissions.revealPlatform`, the audit block no longer lets platform staff reveal restricted details at all; only the service role and tenant members with the reveal key do. Upgrade note: set `revealPlatform` to a platform key and grant it to the staff who need it. Run `better-supabase upgrade`.
