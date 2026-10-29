---
"better-supabase": minor
---

Data lifecycle: export one record with `requestSubjectExport(subjectType, subjectId, { format })`, which calls the new `request_subject_export` function. It collects the record and every installed block's rows attached to it, decrypts encrypted columns and custom field values through the reveal functions as the caller (so `auditReads` tables audit the read), and writes the files through the same exporter. The caller needs `organization.export` or the record's `manage` action. Run `better-supabase upgrade` and generate a migration.

- `data_exports` gains `subject_type`, `subject_id` and `format`, and `subject` accepts `record`. `DataExport` has `subjectType`, `subjectId` and `format`.
- `data_export.requested`, `data_export.completed` and `data_export.failed` carry `subjectType` and `subjectId` (null for user and organization exports).
- A record export's own format wins over the exporter's `format` option.
