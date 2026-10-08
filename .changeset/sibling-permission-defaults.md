---
"better-supabase": patch
---

Module actions whose default is a sibling action's key now follow that key as configured instead of a fixed string. The invitations module's `revoke` and `view` follow `invite` (also in the organizations module's `list_organization_invitations`), the waitlist module's `invite` follows the invitations module's `invite`, billing `viewAll` follows `read`, and audit `viewAll` follows `view`. An app that renames the sibling key no longer has to repeat it for these actions, and `sql upgrade` and doctor list the same keys the functions check. Setting the action itself still overrides it.
