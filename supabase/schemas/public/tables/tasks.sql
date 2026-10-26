-- Owned by you since `better-supabase migrate schema-first`.
create table if not exists "public"."tasks" (
  id uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null references "public"."organizations" ("id") on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table "public"."tasks" add column if not exists "title" text not null;

alter table "public"."tasks" add column if not exists "status" text not null default 'todo';

alter table "public"."tasks" add column if not exists "starts_on" date;

alter table "public"."tasks" add column if not exists "due_on" date;

alter table "public"."tasks" add column if not exists "assignee_id" uuid references auth.users (id) on delete set null;

alter table "public"."tasks" add column if not exists "project_id" uuid not null;

alter table "public"."tasks" add column if not exists "rank" text collate "C" not null default 'V';

alter table "public"."tasks" enable row level security;

revoke all on "public"."tasks" from public, anon, authenticated;

grant select, insert, update, delete on "public"."tasks" to authenticated;

grant all on "public"."tasks" to service_role;

drop policy if exists "tasks_select" on "public"."tasks";

create policy "tasks_select" on "public"."tasks" for select to authenticated using ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists "tasks_insert" on "public"."tasks";

create policy "tasks_insert" on "public"."tasks" for insert to authenticated with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));

drop policy if exists "tasks_update" on "public"."tasks";

create policy "tasks_update" on "public"."tasks" for update to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write())) with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));

drop policy if exists "tasks_delete" on "public"."tasks";

create policy "tasks_delete" on "public"."tasks" for delete to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));

drop policy if exists bsb_tenant_scope on "public"."tasks";

drop policy if exists bsb_tenant_scope_select on "public"."tasks";

create policy bsb_tenant_scope_select on "public"."tasks" as restrictive
  for select to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists bsb_tenant_scope_insert on "public"."tasks";

create policy bsb_tenant_scope_insert on "public"."tasks" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists bsb_tenant_scope_update on "public"."tasks";

create policy bsb_tenant_scope_update on "public"."tasks" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

drop policy if exists bsb_tenant_scope_delete on "public"."tasks";

create policy bsb_tenant_scope_delete on "public"."tasks" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

alter table "public"."tasks" drop constraint if exists "tasks_title_check";

alter table "public"."tasks" add constraint "tasks_title_check" check (char_length("title") <= 200);

alter table "public"."tasks" drop constraint if exists "tasks_status_check";

alter table "public"."tasks" add constraint "tasks_status_check" check ("status" in ('todo', 'doing', 'done'));

alter table "public"."tasks" drop constraint if exists "tasks_project_id_title_key";

alter table "public"."tasks" add constraint "tasks_project_id_title_key" unique ("project_id", "title");

create index if not exists "tasks_organization_id_idx" on "public"."tasks" ("organization_id");

create index if not exists "tasks_assignee_id_idx" on "public"."tasks" ("assignee_id");

create index if not exists "tasks_project_id_idx" on "public"."tasks" ("project_id");

create index if not exists "tasks_status_rank_idx" on "public"."tasks" ("status", "rank");

drop trigger if exists "bsb_updated_at" on "public"."tasks";

create trigger "bsb_updated_at" before update on "public"."tasks"
  for each row execute function better_supabase.set_updated_at();

drop trigger if exists "bsb_emit_event" on "public"."tasks";

create trigger "bsb_emit_event" after insert or update or delete on "public"."tasks"
  for each row execute function "better_supabase"."tasks_emit_event"();

alter table "public"."tasks" drop constraint if exists "tasks_project_id_fkey";

alter table "public"."tasks" add constraint "tasks_project_id_fkey" foreign key ("organization_id", "project_id") references "public"."projects" ("organization_id", id) on delete cascade;

comment on table public.tasks is '@bsb subject type=task id-type=uuid tenant=organization_id title=title url=/projects/{project_id} rank=rank rank-group=status; events include="status, project_id"';
