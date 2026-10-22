# 0071: Drive labels are tags, and file approvals target one attachment

- Status: accepted
- Date: 2026-10-22

## Context

Phase 7 of the SaaS parity track asks for labels on drive items and for
approvals of files. The tags and approvals blocks already apply to any
subject in `config.subjects`, and `drive_node` is one. Both check the
subject with `subjectReadable`, which runs inside security definer
functions, so it bypasses row level security. It only checks that the row
is in the tenant and, optionally, a tenant permission, so any member could
tag a node or list its approvals, while a node's access comes from grants
on the tree. A file also changes under an approval: a new
revision would silently inherit an approval given to the old bytes.

## Decision

Labels are tags. `drive_label` applies or removes a tag through
`tags.tag` and `tags.untag`, and `drive_labeled` lists the readable nodes
with a tag. `drive_node_json` carries `labels`, and purging a node deletes
its taggings. Any tag kind works; no `label` kind is reserved.

A file approval is an approvals request with action `approve` on the node,
whose payload names the attachment and the revision number.
`drive_request_approval` checks that the attachment belongs to the file and
is uploaded, and `drive_approvals` adds whether each request's attachment
is still the file's content. `drive_node_json` carries `approval`, the
latest request for the current attachment, so a new revision clears it and
restoring an approved revision brings it back. The one pending request per
subject and action that approvals already enforces stays: one pending
approval per file.

When a managed drive is installed, tags and approvals wrap their subject
check for `drive_node` in `drive_can` (read for listing, write for tagging
and requesting). The guard casts the id only after a UUID match, because
SQL `and` doesn't promise to evaluate the match first.

## Alternatives considered

- A `drive_labels` table: a second tag system with its own colors and
  admin screens, and labels would not show up in tag search or rules.
- An approval per node without the attachment: a new upload would carry the
  approval of bytes nobody reviewed.
- A new request per revision with the old ones cancelled: the history of
  what was approved would be lost, and restoring a revision couldn't bring
  back its approval.

## Consequences

Anyone who can read a node sees its labels and its approval state,
including viewers. Approval requests outlive a purged node as the record of
what was decided; taggings don't. drive-files renders after tags and
approvals (`SQL_MODULES` order), so it can reference their functions; the
guard in tags and approvals is only rendered when the managed drive is
installed. Adopted drives keep the previous behavior.
