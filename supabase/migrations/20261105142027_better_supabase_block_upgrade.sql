-- better-supabase upgrade: steps that run before the schema diff.

-- attachments: version 8 to 9. Attachments record the SHA-256 of the file's bytes: set_attachment_status takes a sha256 from the scan step, and the row keeps it with hash_verified_at, also on earlier versions.
drop function if exists "better_supabase"."set_attachment_status"(uuid, text, text);
