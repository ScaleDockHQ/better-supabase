-- Columns the blocks add to public.profiles, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "public"."profiles" add column if not exists "email" text;
alter table "public"."profiles" add column if not exists "username" text;
alter table "public"."profiles" add column if not exists "full_name" text;
alter table "public"."profiles" add column if not exists "first_name" text;
alter table "public"."profiles" add column if not exists "last_name" text;
alter table "public"."profiles" add column if not exists "avatar_url" text;
alter table "public"."profiles" add column if not exists "active_organization_id" uuid;
alter table "public"."profiles" add column if not exists "active_team_id" uuid;
alter table "public"."profiles" add column if not exists "onboarding" jsonb not null default '{}';
alter table "public"."profiles" add column if not exists "disabled_at" timestamptz;
alter table "public"."profiles" add column if not exists "updated_at" timestamptz not null default now();
