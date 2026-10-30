# 0140: Store drive text beside the node and check upload quotas in SQL

- Status: accepted
- Date: 2026-10-30

## Context

ADR 0133 makes text extraction a port (`TextExtractor`) that the app
implements. It leaves open where the text lives, how search and knowledge
read it, when the extraction runs, and how an organization's storage is
capped. The text has to follow the node's grants, survive in the search
index only while the file is current, and stay out of the node row that
every drive call reads. Quotas belong to the `usage` block, which already
answers `within_quota` for policies and RPCs.

## Decision

- **A text table in drive core.** `drive_node_texts` holds one row per file
  (`node_id` is the key, deleted with the node) with the attachment it was
  read from, the extractor's name and the content, kept at `maxTextBytes`
  (1 MB by default). Members read a row when `drive_can` gives them the read
  role on the node; only the service role writes, through
  `drive_set_text(node, attachment, content, extractor)`, which stores
  nothing when the attachment is no longer the file's content.
- **Search through a view.** `drive_node_search` (security invoker, service
  role only) joins a node's name to the first 100,000 characters of its
  text. `driveSubject()` points the search entry at the view and watches the
  text table, so a new text reindexes the node. The view exists without
  `drive-files`, with a null content, so the subject stays valid.
- **Extraction runs on the outbox.** `createDriveText` reacts to
  `attachment.uploaded` and `attachment.scanned`, finds the node by its
  current attachment (`drive_text_source`), skips files that aren't clean,
  downloads the object and stores the text. With a knowledge client, it
  replaces the file's knowledge document, scoped to the node as its subject
  (ADR 0124). `plainTextExtractor()` covers text formats without a
  dependency.
- **Quotas in the upload functions.** `quota: { meter }` makes
  `drive_create_file` and `drive_upload_revision` call
  `within_quota(organization, meter, size)` and raise `DRIVE_QUOTA_EXCEEDED`
  (SQLSTATE `53400`) before the object is signed. The service role is not
  checked. `drive-files` with a quota requires `usage`.

The drive and drive-files modules move to version 2.

## Alternatives considered

- **A text column on `drive_nodes`.** Every list and read would carry up to a
  megabyte per file, and the column would sit on app-owned node tables.
- **Extract on `drive.node_created`.** The node exists before its upload is
  confirmed or scanned, so the extractor would read nothing or an unscanned
  file.
- **Bundle a PDF or office extractor as an optional peer.** The useful
  extractors need native tools or a paid service (ADR 0133); a plain-text
  extractor plus the conformance kit covers the free case.
- **Record usage on every commit.** Uploads that are trashed, purged or
  replaced would need matching decrements; a computed `storage` meter over
  the attachments stays correct without them.

## Consequences

Search finds files by their content, and knowledge answers from them, with
the node's grants. Text longer than 100,000 characters is stored but only its
start is indexed. A quota checks the declared size before the upload, so it
trusts the size the client sends; the storage bucket's own size limit still
caps each object. Revisit when an app needs per-page text or OCR coordinates,
which would need a table per page.
