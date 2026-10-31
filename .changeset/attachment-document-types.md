---
"better-supabase": minor
---

Attachments carry per-organization document types with typed metadata, and files can be registered before they are uploaded (breaking).

- `attachments.documentTypes.define`, `list` and `remove` manage types such as `supplier_invoice` with typed fields (`text`, `number`, `amount`, `date`, `expiry`, `boolean`, `select`). A bad value fails with `ATTACHMENT_FIELD_INVALID`.
- Attachments gain `documentTypeId`, `source`, `externalId`, `storageStatus` (`stored`, `pending_upload`, `missing`) and `sourcePath`. `(organization, source, externalId)` is unique, `source` must be in `options.sources` or belong to an import run, and `subjectType` must be a registered subject type.
- The `imports` block gets an `attachment` target that registers the record first. `claim` and `markMissing` finish it later.
- `create_attachment` takes `document_type`, `source`, `external_id` and `source_path`; the old overloads are dropped. A table adopted for `tables.attachments` maps the five new columns or sets them to `null`.

See the 0.46 to 0.47 migration guide, "Attachment document types".
