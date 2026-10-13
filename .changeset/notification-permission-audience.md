---
"better-supabase": minor
---

`send` accepts `permission` (with a tenant) and reaches the users who hold that key. A provider supplies them through `authorization.functions.holdersOf`. The roles and catalog models derive holders from memberships. A provider model without `holdersOf` raises `NOTIFICATION_PERMISSION_AUDIENCE_UNAVAILABLE` instead of notifying every member.
