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
