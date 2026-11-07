-- Columns the blocks add to centrakit.audit_logs, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "centrakit"."audit_logs" add column if not exists "actor_label" text;
alter table "centrakit"."audit_logs" add column if not exists "tenant_label" text;
alter table "centrakit"."audit_logs" add column if not exists "target_label" text;
