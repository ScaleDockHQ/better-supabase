-- Columns the blocks add to centrakit.audit_log_restricted_details, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "centrakit"."audit_log_restricted_details" add column if not exists "changed_values" jsonb;
