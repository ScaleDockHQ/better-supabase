---
"better-supabase": minor
---

Drive files are searchable by their content and can be capped by a usage quota.

- `createDriveText({ transport, storage, extractor, knowledge? })` from `better-supabase/blocks/drive` reads each clean upload through a `TextExtractor` and stores its text in the new `drive_node_texts` table, which follows the node's read grants. Run its `sink()` on the outbox relay. With a knowledge client, the text also becomes a knowledge document scoped to the node. `plainTextExtractor()` reads text, JSON, XML and YAML; `textExtractorOf` and `testTextExtractor` (from `better-supabase/testing`) check your own extractor.
- `driveSubject()` indexes a node's name and the first 100,000 characters of its text through the `drive_node_search` view.
- `blocks.drive.options.quota: { meter }` makes `drive_create_file` and `drive_upload_revision` check `within_quota` for the upload's size and fail with `DRIVE_QUOTA_EXCEEDED`. It needs the `usage` block. `maxTextBytes` (default 1 MB) caps the text kept per file.
- The drive and drive-files modules are version 2. Run `better-supabase upgrade` and generate a migration.
