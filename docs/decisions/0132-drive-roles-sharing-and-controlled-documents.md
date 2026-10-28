# 0132: Drive roles, sharing and controlled documents

- Status: accepted
- Date: 2026-10-28

## Context

The drive has a role ladder (viewer, commenter, editor, owner) and grants
per node. Google Drive parity and a document management system need more:
an upload-only role for intake folders, a commenter role outside the write
ladder, share-link passwords, download control with previews still
readable, file requests, structured metadata, text extraction and preview
rendering, access requests, ownership transfer, a sharing policy and
storage quotas. A controlled-document lifecycle adds numbering, types,
owners, release through approvals, periodic review and local variants.

## Decision

- Roles: `commenter` sits below the write role and is checked through
  `drive_can_comment`. `uploadRole` (`contributor`) is outside the ladder,
  has rank 0 for reading and lets a caller create files in a folder it
  cannot read.
- Share links carry an optional password (bcrypt through `pgcrypto`), a
  `download_allowed` flag and a role from the subject's list (`view`,
  `download`, `upload`).
- Download control: `download_blocked` on a node or a drive blocks originals
  through `drive_object_allowed`. Previews live under a separate prefix
  (`_previews`) so a blocked original still previews, and
  `drive_object_allowed` allows `select` on that prefix with read access.
- Text extraction and preview rendering are versioned ports
  (`TextExtractor`, `PreviewRenderer`, `apiVersion: 1`) over `fetch` or a
  `Blob`; no OCR engine or renderer ships with the library.
- Controlled documents are a drive option (`control`): files get a number,
  type, owner, status (`draft`, `in_review`, `effective`, `obsolete`), an
  effective version released through approvals, a review interval, a next
  review date and `variant_of` relations for local variants.
  Acknowledgements target the effective version.

## Alternatives considered

- **A separate `documents-control` block.** It would need a second file
  store or a foreign key into drive; an option on drive keeps one node
  table.
- **Block downloads by hiding the object.** Previews would stop working,
  which is the main reason to preview a document you may not download.
- **Ship an OCR engine.** It pulls a large binary into every install and
  ages badly; a port lets an app choose.

## Consequences

Apps get Drive-like sharing without a second sharing model. A controlled
document is still a drive node, so search, grants and versions apply.
Blocking downloads is advisory at the storage layer: a writer can always
read the original. Revisit if storage policies need per-preview signing.
