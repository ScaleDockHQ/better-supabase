---
"better-supabase": minor
---

Calendar and drive access can come from the authorization provider's per-row grants, without a hand-written function.

- `blocks.calendar.options.accessFunctions` entries of the form `{ rows, key }` check the signed-in caller through the provider's `rowsWith` template, with their own claims, and anyone else, such as the creator of a share link fetched with nobody signed in, through `rowsWithFor`.
- `blocks.drive.options.roleFunctions.node` and `.drive` take `{ rows, roles }`: the provider's resource and the permission key for each role. The caller gets the highest role whose key they hold.
- `calendar_access` and `calendar_event_access` answer for the caller only and return false for another user unless the service role asks. The calendar feeds check the link's creator through the new `calendar_access_for` and `calendar_event_access_for`, which no client role can execute.
