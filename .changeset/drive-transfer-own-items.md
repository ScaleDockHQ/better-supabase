---
"better-supabase": minor
---

`drive_transfer_ownership` (`drive.transferOwnership`) no longer lets a member with `drive.manage` take another member's items. A member hands over only their own items. Moving someone else's items, as `driveOffboardingSink` does when a member leaves, needs the service role. Before, a member with `drive.manage` could transfer another member's private files to themselves and read them.
