---
"better-supabase": minor
---

Knowledge documents can belong to a record. With the `subjects` block installed, `ingest.text(org, { ..., scope: "subject", subject: { type, id } })` and `documents.create` store the record in the new optional `subject_type` and `subject_id` columns, and a member reads, lists and searches the document only while `can_subject(subject_type, subject_id, 'read')` is true, so a drive folder's knowledge follows the folder's grants. The owner and the manage permission get no exception, the document's collection must still be readable, and system documents stay readable by every organization.

- `create_knowledge_document` and `list_knowledge_documents` take `subject_type text default null, subject_id text default null` at the end. Scope `subject` without both, or a type or id with another scope, fails with `KNOWLEDGE_DOCUMENT_INVALID`; a record the caller can't read fails with `KNOWLEDGE_DOCUMENT_SUBJECT_NOT_FOUND`.
- `documents.list` takes `subject`, a search scope `{ scope: "subject", type, id }` matches one record, and `KnowledgeDocument.subject` returns it. `KnowledgeSubject` is exported from `better-supabase/blocks/knowledge`.
- The knowledge module is version 4. Run `better-supabase upgrade` and generate a migration to add the columns and constraints.
