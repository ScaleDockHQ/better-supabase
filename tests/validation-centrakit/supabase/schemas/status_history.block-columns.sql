-- Columns the blocks add to centrakit.status_history, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "centrakit"."status_history" add column if not exists "actor_name" text;
alter table "centrakit"."status_history" add column if not exists "actor_email" text;
alter table "centrakit"."status_history" add column if not exists "ip_address" inet;
alter table "centrakit"."status_history" add column if not exists "user_agent" text;
