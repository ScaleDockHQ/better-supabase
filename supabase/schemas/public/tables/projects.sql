-- Owned by you since `better-supabase migrate schema-first`.
create table if not exists "public"."projects" (
  id uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null references "public"."organizations" ("id") on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table "public"."projects" add column if not exists "name" text not null;

alter table "public"."projects" add column if not exists "budget_minor" bigint not null default 0;

alter table "public"."projects" add column if not exists "currency" text not null default 'EUR';

alter table "public"."projects" add column if not exists "lead_id" uuid references auth.users (id) on delete set null;

alter table "public"."projects" add column if not exists "label_id" uuid references "better_supabase"."tags" ("id") on delete set null;

alter table "public"."projects" add column if not exists "internal_notes" text;

alter table "public"."projects" add column if not exists "deleted_at" timestamptz;

alter table "public"."projects" enable row level security;

revoke all on "public"."projects" from public, anon, authenticated;

grant select ("id", "organization_id", "created_at", "updated_at", "name", "budget_minor", "currency", "lead_id", "label_id", "deleted_at") on "public"."projects" to authenticated;

grant insert ("id", "organization_id", "created_at", "updated_at", "name", "budget_minor", "currency", "lead_id", "label_id", "deleted_at"), update ("id", "organization_id", "created_at", "updated_at", "name", "budget_minor", "currency", "lead_id", "label_id", "deleted_at") on "public"."projects" to authenticated;

grant delete on "public"."projects" to authenticated;

grant all on "public"."projects" to service_role;

drop policy if exists "projects_select" on "public"."projects";

create policy "projects_select" on "public"."projects" for select to authenticated using ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists "projects_insert" on "public"."projects";

create policy "projects_insert" on "public"."projects" for insert to authenticated with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));

drop policy if exists "projects_update" on "public"."projects";

create policy "projects_update" on "public"."projects" for update to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write())) with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));

drop policy if exists "projects_delete" on "public"."projects";

create policy "projects_delete" on "public"."projects" for delete to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));

drop policy if exists bsb_tenant_scope on "public"."projects";

drop policy if exists bsb_tenant_scope_select on "public"."projects";

create policy bsb_tenant_scope_select on "public"."projects" as restrictive
  for select to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists bsb_tenant_scope_insert on "public"."projects";

create policy bsb_tenant_scope_insert on "public"."projects" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists bsb_tenant_scope_update on "public"."projects";

create policy bsb_tenant_scope_update on "public"."projects" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists bsb_tenant_scope_delete on "public"."projects";

create policy bsb_tenant_scope_delete on "public"."projects" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

create index if not exists "projects_organization_id_idx" on "public"."projects" ("organization_id");

create index if not exists "projects_lead_id_idx" on "public"."projects" ("lead_id");

create index if not exists "projects_label_id_idx" on "public"."projects" ("label_id");

drop trigger if exists "bsb_updated_at" on "public"."projects";

create trigger "bsb_updated_at" before update on "public"."projects"
  for each row execute function better_supabase.set_updated_at();

create unique index if not exists "projects_organization_id_id_key" on "public"."projects" ("organization_id", id);

drop trigger if exists "bsb_search_project_index" on "public"."projects";

create trigger "bsb_search_project_index"
  after insert or delete or update of "id", "organization_id", "name", "deleted_at" on "public"."projects"
  for each row execute function "better_supabase"."search_index_row"('project', 'id');

comment on table public.projects is '@bsb subject type=project id-type=uuid tenant=organization_id title=name url=/projects/{id} deleted-at=deleted_at search versions=name,budget_minor,currency; server internal_notes';
