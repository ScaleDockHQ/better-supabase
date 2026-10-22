---
"better-supabase": minor
---

The drive takes labels and file approvals.

- With the tags block installed, `label(id, tagId, applied?)` puts a tag on a node or takes it off, and `labeled(organizationId, tagId)` lists the nodes with a tag. Every node carries `labels`.
- With the approvals block installed, `requestApproval(id, { attachmentId, reason })` asks for approval of the file's current content or of one earlier revision, and `approvals(id)` lists the requests with `attachmentId`, `revision` and `current`. Every node carries `approval`, the request for its current content, so a new upload clears it and restoring an approved revision brings it back. Add a policy for the `approve` action on `drive_node`.
- New types: `DriveLabel`, `DriveApprovalState` and `DriveApproval`.

With a managed drive installed, the tags and approvals functions now check the drive grants for `drive_node` subjects: reading tags or listing requests needs read access to the node, and tagging or requesting approval needs write access. Before, any member of the organization could do both. Run `better-supabase sql sync`, then generate a migration.
