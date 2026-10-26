-- Owned by you since `better-supabase migrate schema-first`.
create table if not exists "public"."saved_views" (
  id uuid primary key default gen_random_uuid(),
  "user_id" uuid default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table "public"."saved_views" add column if not exists "name" text not null;

alter table "public"."saved_views" add column if not exists "filters" jsonb not null default '{}';

alter table "public"."saved_views" enable row level security;

revoke all on "public"."saved_views" from public, anon, authenticated;

grant select, insert, update, delete on "public"."saved_views" to authenticated;

grant all on "public"."saved_views" to service_role;

drop policy if exists "saved_views_select" on "public"."saved_views";

create policy "saved_views_select" on "public"."saved_views" for select to authenticated using ("user_id" = (select auth.uid()));

drop policy if exists "saved_views_insert" on "public"."saved_views";

create policy "saved_views_insert" on "public"."saved_views" for insert to authenticated with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

drop policy if exists "saved_views_update" on "public"."saved_views";

create policy "saved_views_update" on "public"."saved_views" for update to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write())) with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

drop policy if exists "saved_views_delete" on "public"."saved_views";

create policy "saved_views_delete" on "public"."saved_views" for delete to authenticated using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

create index if not exists "saved_views_user_id_idx" on "public"."saved_views" ("user_id");

drop trigger if exists "bsb_updated_at" on "public"."saved_views";

create trigger "bsb_updated_at" before update on "public"."saved_views"
  for each row execute function better_supabase.set_updated_at();
