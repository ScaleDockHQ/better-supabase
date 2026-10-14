---
"better-supabase": minor
---

Add the `access-requests` block (`better-supabase/blocks/access-requests` and the `access-requests` SQL module): members ask for a role, for a set time if they like, and the request goes through the approvals module. The final approval grants the role, `end()` and `expire_access_grants()` put the previous role back, and the module records `access.requested`, `access.request_approved` and `access.ended`. With the `provider` access model the adapter grants the role from the events. Approvals gains an internal `open_approval` that files a request under an explicit policy.
