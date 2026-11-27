---
"better-supabase": patch
---

`drive_transfer_ownership` no longer fails when the new owner can't own one of the drives, such as a second personal drive that the app's unique index or check over the owner column refuses. That drive stays with the old owner together with its drive grants and the top-role grants on its files, the other drives move, and the result lists it in `keptDriveIds` (`DriveTransfer.keptDriveIds` in the client). Any other unique or check violation still fails the transfer. `driveOffboardingSink` passes kept drives to a new `onKept` option, or logs a warning without it.
