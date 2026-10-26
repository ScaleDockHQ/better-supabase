-- Owned by you since `better-supabase migrate schema-first`.
create table if not exists "public"."client_notes" (
  id uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null references "public"."organizations" ("id") on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table "public"."client_notes" add column if not exists "client_name" text not null;

alter table "public"."client_notes" add column if not exists "diagnosis" text;

alter table "public"."client_notes" add column if not exists "birth_date" text;

alter table "public"."client_notes" enable row level security;

revoke all on "public"."client_notes" from public, anon, authenticated;

grant select ("id", "organization_id", "created_at", "updated_at", "client_name") on "public"."client_notes" to authenticated;

grant insert ("id", "organization_id", "created_at", "updated_at", "client_name", "diagnosis", "birth_date"), update ("id", "organization_id", "created_at", "updated_at", "client_name", "diagnosis", "birth_date") on "public"."client_notes" to authenticated;

grant delete on "public"."client_notes" to authenticated;

grant all on "public"."client_notes" to service_role;

drop policy if exists "client_notes_select" on "public"."client_notes";

create policy "client_notes_select" on "public"."client_notes" for select to authenticated using ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists "client_notes_insert" on "public"."client_notes";

create policy "client_notes_insert" on "public"."client_notes" for insert to authenticated with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));

drop policy if exists "client_notes_update" on "public"."client_notes";

create policy "client_notes_update" on "public"."client_notes" for update to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write())) with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));

drop policy if exists "client_notes_delete" on "public"."client_notes";

create policy "client_notes_delete" on "public"."client_notes" for delete to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));

drop policy if exists bsb_tenant_scope on "public"."client_notes";

drop policy if exists bsb_tenant_scope_select on "public"."client_notes";

create policy bsb_tenant_scope_select on "public"."client_notes" as restrictive
  for select to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists bsb_tenant_scope_insert on "public"."client_notes";

create policy bsb_tenant_scope_insert on "public"."client_notes" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists bsb_tenant_scope_update on "public"."client_notes";

create policy bsb_tenant_scope_update on "public"."client_notes" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists bsb_tenant_scope_delete on "public"."client_notes";

create policy bsb_tenant_scope_delete on "public"."client_notes" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

create index if not exists "client_notes_organization_id_idx" on "public"."client_notes" ("organization_id");

drop trigger if exists "bsb_updated_at" on "public"."client_notes";

create trigger "bsb_updated_at" before update on "public"."client_notes"
  for each row execute function better_supabase.set_updated_at();

drop trigger if exists "bsb_seal_fields" on "public"."client_notes";

create trigger "bsb_seal_fields" before insert or update of "organization_id", "diagnosis", "birth_date" on "public"."client_notes"
  for each row execute function "better_supabase"."client_notes_seal"();

comment on table public.client_notes is '@bsb encrypted diagnosis=text birth_date=date';
