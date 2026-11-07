-- better-supabase module: field-history
-- @bsb-block field-history@1 managed
-- @bsb-hash sha256:01a19fba9c24f804b4e005ae88c21ff7809a9b3b715c614ace4361a5b62951a3
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table "better_supabase"."field_changes" (
  "id" bigint generated always as identity primary key,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "field" text not null,
  "old_value" jsonb,
  "new_value" jsonb,
  "changed_by" uuid references auth.users (id) on delete set null,
  "changed_at" timestamptz not null default now()
);
create index field_changes_subject_idx on "better_supabase"."field_changes" ("subject_type", "subject_id", "id" desc);
create index field_changes_tenant_idx on "better_supabase"."field_changes" ("tenant_id", "changed_at");
create index field_changes_changed_by_idx on "better_supabase"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "better_supabase"."field_changes" enable row level security;
revoke all on "better_supabase"."field_changes" from public, anon, authenticated;
grant select on "better_supabase"."field_changes" to authenticated;
grant all on "better_supabase"."field_changes" to service_role;
create policy bsb_field_changes_read on "better_supabase"."field_changes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));

-- Keeps the old and new value of each watched column of a work_item on update.
create or replace function better_supabase.bsb_field_history_work_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into "better_supabase"."field_changes" ("tenant_id", "subject_type", "subject_id", "field", "old_value", "new_value", "changed_by")
  select new."tenant_id", 'work_item', new."id"::text, x.field, x.old_value, x.new_value, auth.uid()
  from (values
      ('title', to_jsonb(old."title"), to_jsonb(new."title")),
      ('body', to_jsonb(old."body"), to_jsonb(new."body"))
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_field_history_work_item() from public, anon, authenticated;
create trigger bsb_field_history_work_item after update of "title", "body" on "better_supabase"."work_items"
for each row execute function better_supabase.bsb_field_history_work_item();

-- Keeps the old and new value of each watched column of a deal on update.
create or replace function better_supabase.bsb_field_history_deal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into "better_supabase"."field_changes" ("tenant_id", "subject_type", "subject_id", "field", "old_value", "new_value", "changed_by")
  select new."tenant_id", 'deal', new."id"::text, x.field, x.old_value, x.new_value, auth.uid()
  from (values
      ('amount', to_jsonb(old."amount"), to_jsonb(new."amount")),
      ('stage_id', to_jsonb(old."stage_id"), to_jsonb(new."stage_id")),
      ('owner_id', to_jsonb(old."owner_id"), to_jsonb(new."owner_id")),
      ('expected_close_on', to_jsonb(old."expected_close_on"), to_jsonb(new."expected_close_on"))
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_field_history_deal() from public, anon, authenticated;
create trigger bsb_field_history_deal after update of "amount", "stage_id", "owner_id", "expected_close_on" on "better_supabase"."deals"
for each row execute function better_supabase.bsb_field_history_deal();

-- Keeps the old and new value of each watched column of a company on update.
create or replace function better_supabase.bsb_field_history_company()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into "better_supabase"."field_changes" ("tenant_id", "subject_type", "subject_id", "field", "old_value", "new_value", "changed_by")
  select new."tenant_id", 'company', new."id"::text, x.field, x.old_value, x.new_value, auth.uid()
  from (values
      ('owner_id', to_jsonb(old."owner_id"), to_jsonb(new."owner_id")),
      ('lifecycle', to_jsonb(old."lifecycle"), to_jsonb(new."lifecycle"))
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_field_history_company() from public, anon, authenticated;
create trigger bsb_field_history_company after update of "owner_id", "lifecycle" on "better_supabase"."companies"
for each row execute function better_supabase.bsb_field_history_company();

-- A record's changes, newest first, optionally of one field. before is the id
-- of the last change of the previous page. Needs history.read and read access
-- to the record.
create or replace function "better_supabase"."field_history"(subject_type text, subject_id text, field text default null, before bigint default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', z."id"::text,
    'organizationId', z."tenant_id",
    'subjectType', z."subject_type",
    'subjectId', z."subject_id",
    'field', z."field",
    'before', z."old_value",
    'after', z."new_value",
    'changedBy', z."changed_by",
    'changedAt', z."changed_at"
  ) order by z."id" desc), '[]'::jsonb)
  from (
    select x.* from "better_supabase"."field_changes" x
    where x."subject_type" = field_history.subject_type
      and x."subject_id" = field_history.subject_id
      and (field_history.field is null or x."field" = field_history.field)
      and (field_history.before is null or x."id" < field_history.before)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'field_history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."field_changes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."field_changes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."field_changes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."field_changes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.field-history.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."field_history"(subject_type text, subject_id text, field text default null, before bigint default null, max_count integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."field_history"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "api"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;
