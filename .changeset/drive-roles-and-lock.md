---
"better-supabase": minor
---

The drive checks files out, blocks downloads and serves rendered previews. `drive.lock(id, { until, note })` checks a file out for the caller (8 hours by default, at most 30 days) and `unlock(id, { force })` ends it; while a lock applies, nobody else may upload, commit, restore a revision, rename, move, trash or delete the file, or trash or delete a folder above it (`DRIVE_LOCKED`, code `55P03`). The share role breaks someone else's lock with `force`, and the service role ignores locks. Nodes carry `lockedBy`, `lockedUntil` and `lockNote`.

`drive.blockDownloads(id)` keeps the original of a node and everything under it from callers below the write role, and `blockDriveDownloads(driveId)` does the same for a drive. Blocked callers still open the node and read its previews; `download` fails with `DRIVE_DOWNLOAD_BLOCKED`, and the storage policy refuses the original. Nodes carry `downloadBlocked` and `downloadable`, and `drive_can_download(node)` is the SQL check.

`createDrivePreviews({ transport, storage, renderer })` renders a file's pages through a versioned `PreviewRenderer` (`apiVersion: 1`) and stores them under the new `previewPrefix` option (default `_previews`), which readers may open even when downloads are blocked. Its `sink()` renders on `attachment.uploaded` and `attachment.scanned`, and its `job` runs from a queue. `drive.previews(id)` and `previewUrls(id)` read the pages.

A `commenter` role in `roles` becomes the new `commentRole`, checked by `drive_can_comment(node)`, which `driveSubject()` now uses for the `comment` action. Drive share links take the `view`, `download` and `upload` roles; creating one now needs the drive's share role on the node, an `upload` link must name a folder, and `drive.link(token)` honors the link's `downloadAllowed` and any download block, refuses upload links with `DRIVE_LINK_ROLE_INVALID` and returns the node's `previews`.

The drive records `drive.node_locked`, `drive.node_unlocked`, `drive.node_download_blocked_changed` and `drive.download_blocked_changed`. The node table gains `locked_by`, `locked_until`, `lock_note`, `download_blocked` and `preview_pages`, and with `drives` on the drive table gains `download_blocked`. Over your own tables, map these columns or set them to `null` to leave the feature out. Run `better-supabase upgrade` and generate a migration to pick up the columns and functions.
