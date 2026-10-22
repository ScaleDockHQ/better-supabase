-- better-supabase module: field-history
-- @bs-module field-history@1 managed
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table if not exists "better_supabase"."field_changes" (
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
create index if not exists field_changes_subject_idx on "better_supabase"."field_changes" ("subject_type", "subject_id", "id" desc);
create index if not exists field_changes_tenant_idx on "better_supabase"."field_changes" ("tenant_id", "changed_at");
create index if not exists field_changes_changed_by_idx on "better_supabase"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "better_supabase"."field_changes" enable row level security;
revoke all on "better_supabase"."field_changes" from anon, authenticated;
grant select on "better_supabase"."field_changes" to authenticated;
grant all on "better_supabase"."field_changes" to service_role;
drop policy if exists field_changes_read on "better_supabase"."field_changes";
create policy field_changes_read on "better_supabase"."field_changes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('history.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));

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
      ('owner_user_id', to_jsonb(old."owner_user_id"), to_jsonb(new."owner_user_id")),
      ('expected_close_on', to_jsonb(old."expected_close_on"), to_jsonb(new."expected_close_on"))
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_field_history_deal() from public, anon, authenticated;
drop trigger if exists bsb_field_history_deal on "better_supabase"."deals";
create trigger bsb_field_history_deal after update of "amount", "stage_id", "owner_user_id", "expected_close_on" on "better_supabase"."deals"
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
      ('owner_user_id', to_jsonb(old."owner_user_id"), to_jsonb(new."owner_user_id")),
      ('lifecycle', to_jsonb(old."lifecycle"), to_jsonb(new."lifecycle"))
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_field_history_company() from public, anon, authenticated;
drop trigger if exists bsb_field_history_company on "better_supabase"."companies";
create trigger bsb_field_history_company after update of "owner_user_id", "lifecycle" on "better_supabase"."companies"
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
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

-- blocks.field-history.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."field_history"(subject_type text, subject_id text, field text default null, before bigint default null, max_count integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."field_history"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "api"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
