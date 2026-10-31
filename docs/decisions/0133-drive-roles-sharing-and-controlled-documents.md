# 0133: Give drive commenter and upload-only roles, link controls, preview and text ports, and controlled documents

- Status: accepted
- Date: 2026-10-29

## Context

The `drive` block (ADR 0025, ADR 0071) has a ladder of roles (viewer,
editor, owner), grants per node and share links. Document management and
quality systems need more than that:

- People who may comment but not edit, and people who may drop files into a
  folder without seeing what is in it (a supplier sending certificates).
- Share links with a password, and links that let people view a file
  without downloading the original.
- Text from PDFs and office files for search and retrieval, and page
  previews for files the browser can't show.
- Controlled documents: a number, a type, an owner, a draft, review and
  effective lifecycle with an approved release, a periodic review, and
  readers who see only the effective version.

## Decision

- **Roles outside the ladder.** `commentRole` (default `commenter` when the
  roles list it) lets a holder comment through `drive_can_comment`.
  `uploadRole` is not on the ladder and has no read rank: a holder can
  create files in a folder (`drive_can_upload`) and gets back only the new
  file's id and upload path.
- **Share links.** Links take an optional password and a `download_allowed`
  flag, and a link with role `upload` turns a folder into a file request.
- **Download block with previews on their own path.** `download_blocked` on a
  node or a drive stops downloads of originals for readers below the write
  role. Previews live under a separate prefix (`previewPrefix`, default
  `_previews`) that read access alone allows, so a blocked download never
  blocks a preview.
- **Ports.** `TextExtractor` and `PreviewRenderer` are versioned interfaces
  (`apiVersion: 1`, checked by `textExtractorOf` and `previewRendererOf`).
  The app implements them with any service; drive stores the text for search
  and knowledge, and the pages under the preview prefix.
- **Controlled documents as a drive option.** `control: { types,
  reviewMonths, releaseRole }` adds document columns to `drive_nodes`, a
  state machine (`draft`, `in_review`, `effective`, `obsolete`), numbering,
  a release through `approvals` that freezes a version, periodic reviews
  through `reminders`, and acknowledgements of the effective version (ADR
  0132). Readers below the write role read the effective version only.

## Alternatives considered

- **Put commenter and upload-only on the ladder.** A ladder role inherits
  every lower role; an upload-only role must not include read, and a
  commenter below viewer makes no sense.
- **Block previews with downloads.** Teams block downloads to stop copies of
  originals, not to stop people reading; a preview carve-out keeps the file
  usable.
- **Bundle an extractor and a renderer.** Text extraction and rendering need
  native tools or a paid service; a port keeps the core free of them, in
  line with architecture invariant 1.
- **A separate `documents-control` block.** It would duplicate drive's
  grants, storage paths and share links for every controlled file. An option
  on drive keeps one file tree.

## Consequences

Drive gains columns, functions and two ports, all behind options, so an app
that sets none of them renders the same SQL. Apps that turn on `control`
must install `numbering`, `versions`, `approvals` and `state-machine`; the
build fails with a `TypeError` naming the missing one. The preview prefix is
part of the storage policy, so changing it later orphans existing previews.
Revisit when a WOPI editor or a sync client needs locks or a changes feed
that the node columns can't express.

## Amendment: upload-only grants and file requests (2026-10-30)

- The upload role is accepted on node grants only, and only on folders
  (`DRIVE_ROLE_UNKNOWN` with the reason `upload role is for folders`). It
  needs the node table's `createdBy` column: a contributor may upload a
  revision of a file they added and commit it, through `drive_uploaded_own`,
  and nothing else. `drive_create_file` takes a free name for a caller who
  can't read the folder, so the result never reveals the names it holds.
- A file request is a `drive_link_upload` call on an upload link. It runs
  the share link's password and use checks, creates the file with `source`
  `request` and no creator, and is rate limited per link (`drive_link_upload`
  scope, 20 an hour) when `rate-limit` is installed. Request files stay
  writable for the folder's editors; only mirrored sources are read-only.
- `drive_request_files` wraps `create_share_link` with the role `upload`, so
  the drive's share role check applies before the link exists.
- None of the new functions are in the drive modules' custom contract, so
  an app that implements the drive itself keeps working without them.

## Amendment: controlled documents as built (2026-10-30)

- The state machine is named after the drive's subject type (`drive_node`)
  and has no initial status, so files outside control have none. Its
  transitions are `draft` to `in_review`, `in_review` to `draft` or
  `effective` (the second needs approval), and `effective` to `obsolete`.
- A release runs through the approvals action `release` on the node
  subject. `drive_document_release` is service-only, or runs inside an
  approved release request; the app configures the `drive_node.release`
  policy. `drive.approvals()` keeps listing only `approve` requests.
- Revising an effective document doesn't move it back to `in_review`: it
  stays effective on the released version while the release request is
  pending, and only a document in review goes back to `draft` on a
  rejection. Readers never lose the effective version during a revision.
- Periodic reviews don't use `reminders`. `notify_due_drive_reviews()`
  records `drive.node_review_requested` (and a notification to the owner)
  once per review date, and the app schedules it; the register filter is
  `reviewDue`. An event `drive.node_document_saved` records the type and
  owner changes.
- Numbers come from one `DOC-{n:5}` sequence per organization. Per-type
  formats (`SOP-{n:4}`) need numbering formats keyed by a column and are
  left for later.
- Acknowledgements are contributed only when the app lists `drive_node` in
  `acknowledgements.on`. Unknown register filter keys are ignored.

## Amendment: access requests, ownership transfer and the sharing policy (2026-10-30)

- Access requests on nodes run through the access-requests block, not a
  drive table. `driveSubject({ accessRequests })` declares the record team
  those requests need, and the drive contributes an access grant with two
  functions: `drive_grant_access` adds or removes a node grant marked
  `access_request`, and `drive_access_approvers` names the node's top-role
  holders, who approve when the record has no team lead. Ending a request
  removes only the marked grant, so hand-made shares survive. The client
  names the action (`read`, `comment` or `write`) instead of a drive role,
  since the request is about what the member may do.
- The access-requests client reaches the drive through a new
  `recordAccess` port, optional for the drive, so the drive never imports
  the block. `list_record_access_requests` serves both blocks.
- An approved request is a grant, not a team row. Adding a node's team
  member by hand widens the node's comments and attachments but not the
  node itself; we document this instead of reading teams in drive RLS,
  which would put a second source of truth on every drive read.
- `drive_transfer_ownership` moves top-role grants and, with drives on,
  drive grants and drive owners in one call, and `driveOffboardingSink`
  runs it from `organization.member_removed` and `employee.offboarded`. It
  throws on failure so the outbox retries.
- The sharing policy is one organization setting, `drive.sharing`
  (`{ guests, links }`), read through `drive_sharing(tenant)` with defaults
  when the settings block is absent. Guests are refused with a trigger on
  `guest_grants`, rendered by drive-files, because the guests block writes
  that table itself. `links: "organization"` is checked where links open
  (`drive_link`, `drive_link_upload`); `drive_share` to members is never
  restricted.

## Amendment: a WOPI host on the check-out lock (2026-10-31)

ADR 0166 adds `createWopiHost`. It is the WOPI editor this ADR said to
revisit: the editor's lock id lives in `lockNote` on the existing check-out
lock, so no column or table is added.
