-- Change requests move through the stages of the tenant's published
-- `change-requests` workflow (the state-machine block's `workflow` option).
create table if not exists "public"."change_requests" (
  id uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null references "public"."organizations" ("id") on delete cascade,
  "title" text not null check (char_length("title") between 1 and 200),
  "status" text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table "public"."change_requests" enable row level security;

revoke all on "public"."change_requests" from public, anon, authenticated;

grant select, insert, update, delete on "public"."change_requests" to authenticated;

grant all on "public"."change_requests" to service_role;

drop policy if exists "change_requests_select" on "public"."change_requests";

create policy "change_requests_select" on "public"."change_requests" for select to authenticated using ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists "change_requests_insert" on "public"."change_requests";

create policy "change_requests_insert" on "public"."change_requests" for insert to authenticated with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));

drop policy if exists "change_requests_update" on "public"."change_requests";

create policy "change_requests_update" on "public"."change_requests" for update to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write())) with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));

drop policy if exists "change_requests_delete" on "public"."change_requests";

create policy "change_requests_delete" on "public"."change_requests" for delete to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));

drop policy if exists bsb_tenant_scope_select on "public"."change_requests";

create policy bsb_tenant_scope_select on "public"."change_requests" as restrictive
  for select to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists bsb_tenant_scope_insert on "public"."change_requests";

create policy bsb_tenant_scope_insert on "public"."change_requests" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists bsb_tenant_scope_update on "public"."change_requests";

create policy bsb_tenant_scope_update on "public"."change_requests" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists bsb_tenant_scope_delete on "public"."change_requests";

create policy bsb_tenant_scope_delete on "public"."change_requests" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

create index if not exists "change_requests_organization_id_idx" on "public"."change_requests" ("organization_id");

drop trigger if exists "bsb_updated_at" on "public"."change_requests";

create trigger "bsb_updated_at" before update on "public"."change_requests"
  for each row execute function better_supabase.set_updated_at();

comment on table public.change_requests is '@bsb subject type=change_request id-type=uuid tenant=organization_id title=title url=/change-requests/{id}';
