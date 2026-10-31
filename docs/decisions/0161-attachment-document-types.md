# 0161: Attachments take document types, a source and metadata-first records

- Status: accepted
- Date: 2026-10-31

## Context

An organization that moves its documents from another system needs to keep
the outside id of each file, the kind of document it is, and the typed facts
about it (amount, date, expiry), and it needs to register thousands of files
before the bytes arrive. Attachments only knew a name, a size and a free
metadata object.

## Decision

- `attachment_document_types(organization, key, name, fields jsonb)` holds the
  types per organization. A field is `{ type, required?, options? }` with the
  types `text`, `number`, `amount`, `date`, `expiry`, `boolean`, `select`.
  `attachment_schema_error` validates a schema and `attachment_fields_error`
  validates a record's metadata in a guard trigger, so every write path is
  checked. Keys a type doesn't declare are kept.
- `attachments` gains `document_type_id`, `source`, `external_id`,
  `storage_status` and `source_path`. The existing scan `status` stays, so the
  storage state has its own column. The guard derives `storage_status` from
  `uploaded_at`.
- `source` is checked against `options.sources` or an import run's source.
  `(organization, source, external_id)` is a unique index, the organization-wide
  external id index. `subject_type` is checked against
  `better_supabase.subject_types()`.
- The `imports` block gets an `attachment` target (`import_attachment`) that
  registers a pending record. `claim_attachment_upload` and
  `mark_attachment_missing` finish it, and fail with `ATTACHMENT_NOT_CLAIMABLE`
  for a stored file.
- Failures carry hint codes: `ATTACHMENT_FIELD_INVALID`,
  `ATTACHMENT_DOCUMENT_SCHEMA_INVALID`, `ATTACHMENT_DOCUMENT_TYPE_UNKNOWN`,
  `ATTACHMENT_DOCUMENT_TYPE_IN_USE`, `ATTACHMENT_SOURCE_UNKNOWN`,
  `ATTACHMENT_SUBJECT_UNKNOWN`, `ATTACHMENT_EXTERNAL_ID_TAKEN`.

## Consequences

- Breaking: `create_attachment` changes signature and the old overloads are
  dropped. A table adopted for attachments maps the five columns or sets them
  to `null`, and the guard renders only when all five are mapped.
- A metadata-first record has size 0 and the type `application/octet-stream`
  until the file replaces them.
