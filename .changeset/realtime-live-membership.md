---
"better-supabase": minor
---

Tenant topics of `realtime-tables` (`bsb:t:<table>:<tenant>`) are now received by members of that tenant at the time of the message, checked with `member_organization_ids()`, instead of by whoever carries the tenant id in their token. A removed member stops receiving at once. Without the `memberships` module tenant topics stay closed; unscoped and own-user topics are unchanged.
