# 0025: Build the drive on attachments, in two modules that render around the subject checks

- Status: accepted
- Date: 2026-10-14

## Context

Apps need folders and files with sharing: a file manager, a document
library, CentraKit's `file_node` tree. The attachments module already stores
uploads with scanning and signed URLs, versions keeps numbered snapshots,
trash keeps a bin and share-links keeps links and per-user state. A drive
built on its own storage would repeat all four.

A drive node should also be a subject, so comments, reactions and
attachments can sit on it. Those modules render `case` checks that name each
subject's table, so the node table has to exist before they render. But the
file side of the drive reads the attachments table, which renders after
comments. One module can't come both before and after them.

SQL module files are numbered by their position in `SQL_MODULES`, and apps
commit the generated files. Inserting a module in the middle of the
registry would renumber every file after it.

## Decision

The drive is two modules. `drive` holds the tree, grants, sharing, the
name-conflict policy and the access checks (`drive_role`, `drive_can`).
`drive-files` holds what needs the other blocks: file nodes on attachment
rows, revisions through versions, restrictive policies on the attachment
rows and on `storage.objects`, the bin through trash, stars and recent items
through share-links' user state, folder links and the purge. `drive`
requires `drive-files`, so `sql add drive` installs both.

A module can set `before: "<module>"`. It renders just before that module,
and its file takes the number of the module ahead of the target, so no other
file is renumbered. `drive` sets `before: "comments"`; both drive modules
stay at the end of `SQL_MODULES`.

A grant applies to the node and everything under it, and a caller's role is
the highest role granted on the node or an ancestor. Grants name a user, a
team or an organization role. In adopt mode a grant table can use a `user`
and a `team` column instead of a principal type and id, and a node table
without an attachment column keeps the tree and the checks without uploads.

The automatic read-only guard (ADR 0019) only sees writes in a function's
own body. Drive functions that write only through internal helpers call
`raise_actor_readonly()` themselves, and `trash_restore_batch` leaves the
delete of the batch to its callers so their bodies show the write.

## Consequences

- Revisions, the bin, stars and links work only with versions, trash and
  share-links installed; without them the matching calls are not rendered.
- `drive.node_purged` carries the object paths, and `prune()` deletes them
  from storage, because the database can't delete storage objects.
- `before` is a general mechanism, but only a module whose table must exist
  before the subject checks should use it.
- Relations and search can use `drive_node` as a subject through
  `driveSubject()` once they are on the same branch.
