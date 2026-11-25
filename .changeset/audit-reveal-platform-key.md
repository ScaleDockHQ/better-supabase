---
"better-supabase": minor
---

`reveal_audit_entry` and `reveal_audit_entries` let platform staff reveal restricted audit details only with `permissions.revealPlatform`, which falls back to the `reveal` key on the platform, instead of the read-all key. Platform staff who only read every tenant's log no longer see IP addresses, user agents and row snapshots. Set `revealPlatform` to your platform reveal key and run `better-supabase upgrade`.
