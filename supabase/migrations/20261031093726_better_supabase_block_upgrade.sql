-- better-supabase upgrade: steps that run before the schema diff.

-- attachments: version 7 to 8. Attachments gain document types with typed metadata fields, a source and external id that are unique per organization, a storage status and a source path; create_attachment takes the document type key, source, external id and source path after pages, a subject type must be registered, and claim_attachment_upload, mark_attachment_missing and an attachment import target register records before their files exist.
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer);
drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer, jsonb);
