---
"better-supabase": minor
---

Drive files can be controlled documents with a number, a type, an owner, a release workflow and periodic reviews.

- `blocks.drive.options.control: { types, reviewMonths?, releaseRole? }` turns it on. It needs the `numbering`, `versions`, `approvals` and `state-machine` blocks, and an approvals policy for the `release` action on `drive_node`.
- The drive client gains `saveDocument`, `submitDocument`, `releaseDocument`, `obsoleteDocument`, `reviewDocument`, `documents` (the register, with `type`, `status`, `ownerId`, `reviewDue` and `search` filters) and `notifyDueReviews`. Each node carries `document` with its number, status, effective version and next review date.
- A document moves from `draft` through `in_review` to `effective` when its release request is approved, and to `obsolete` when withdrawn. Members below the write role download and read only the effective version, and the storage policy refuses the working copy for them.
- With acknowledgements on `drive_node`, each release asks the assigned members to acknowledge the new version. With relations, documents link through the `variant_of` kind.
- New events: `drive.node_document_saved`, `drive.node_submitted`, `drive.node_released`, `drive.node_obsoleted`, `drive.node_reviewed` and `drive.node_review_requested`.
- The `document-register` recipe shows the register in a ReUI data grid. Run `better-supabase upgrade` and generate a migration after setting `control`.
