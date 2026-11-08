-- Columns the blocks add to public.memberships, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "public"."memberships" add column if not exists "updated_at" timestamptz not null default now();
alter table "public"."memberships" add column if not exists "last_used_at" timestamptz;
