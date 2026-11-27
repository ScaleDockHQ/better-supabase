---
"better-supabase": patch
---

`drive_transfer_ownership` no longer fails when the new owner can't own one of the drives, such as a second personal drive that the app's unique index or check refuses. The drive and its grants stay with the old owner, the other drives move, and the result lists the drive in `keptDriveIds` (`DriveTransfer.keptDriveIds` in the client).
