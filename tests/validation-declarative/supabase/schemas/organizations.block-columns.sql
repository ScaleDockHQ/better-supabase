-- Columns the blocks add to public.organizations, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "public"."organizations" add column if not exists "created_by" uuid references auth.users (id) on delete set null;
alter table "public"."organizations" add column if not exists "disabled_at" timestamptz;
alter table "public"."organizations" add column if not exists "deleted_at" timestamptz;
alter table "public"."organizations" add column if not exists "updated_at" timestamptz not null default now();
