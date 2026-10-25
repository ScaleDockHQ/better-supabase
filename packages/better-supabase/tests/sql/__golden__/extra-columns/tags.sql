-- ==== schema supabase/schemas/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block tags@2 managed
-- @bsb-hash sha256:54197b0961d4ff93dc158f586d0caadec7825a3b800659db621062cbb04ae573
-- Tenant tags with a kind, and a link from a tag to a subject. Over the app's tables it can use one link table per subject.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."tags";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."taggings";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."tags" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null,
  "name" text not null check (length("name") between 1 and 80),
  "slug" text not null,
  "color" text,
  "description" text,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "kind", "slug")
);
alter table "better_supabase"."tags" add column if not exists "app_note" text;
alter table "better_supabase"."tags" enable row level security;
revoke all on "better_supabase"."tags" from anon, authenticated;
grant select on "better_supabase"."tags" to authenticated;
grant all on "better_supabase"."tags" to service_role;
create table if not exists "better_supabase"."taggings" (
  "tenant_id" uuid not null,
  "tag_id" uuid not null references "better_supabase"."tags" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "created_at" timestamptz not null default now(),
  primary key ("tag_id", "subject_type", "subject_id")
);
create index if not exists "taggings_subject_idx" on "better_supabase"."taggings" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."taggings" enable row level security;
revoke all on "better_supabase"."taggings" from anon, authenticated;
grant select on "better_supabase"."taggings" to authenticated;
grant all on "better_supabase"."taggings" to service_role;

-- fields: the extra columns (blocks.tags.options.extraColumns) to set.
drop function if exists "better_supabase"."create_tag"(uuid, text, text, text, text);
drop function if exists "better_supabase"."create_tag"(uuid, text, text, text, text, jsonb);
drop function if exists "better_supabase"."create_tag"(uuid, text, text, text, text, text);
create or replace function "better_supabase"."create_tag"(tenant uuid, kind text, name text, color text, description text, slug text default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := coalesce(create_tag.slug, trim(both '-' from regexp_replace(lower(create_tag.name), '[^a-z0-9]+', '-', 'g')));
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if create_tag.slug is not null and create_tag.slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'a slug is lowercase letters and digits joined by single hyphens' using errcode = '22023', hint = 'TAG_SLUG_INVALID';
  end if;
  select max(t."rank" collate "C") into v_last from "better_supabase"."tags" t
    where t."tenant_id" = create_tag.tenant and t."kind" = create_tag.kind;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."tags" ("tenant_id", "kind", "name", "slug", "color", "description", "rank", "created_at")
  values (create_tag.tenant, create_tag.kind, create_tag.name, v_slug, create_tag.color, create_tag.description, v_rank, now())
  returning "id" into v_id;
  update "better_supabase"."tags" x set "app_note" = case when create_tag.fields ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."tags", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(create_tag.fields) e where e.key in ('app_note'))) r
  where x."id" = v_id;
  null;
  return (select jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank, 'fields', jsonb_build_object('app_note', x."app_note")) from "better_supabase"."tags" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_tag"(uuid, text, text, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_tag"(uuid, text, text, text, text, text, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."tag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "better_supabase"."tags" where "id" = tag.tag_id and "tenant_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when '' then true
    else true
  end) then
    raise exception 'tag kind is not allowed on this subject' using errcode = '22023', hint = 'TAG_KIND_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_tag_apply"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using tag.tenant, tag.subject_type, tag.subject_id, tag.tag_id;
    end if;
  end;
  case tag.subject_type
    when '' then null;
    else
      insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
      values (tag.tenant, tag.tag_id, tag.subject_type, tag.subject_id)
      on conflict do nothing;
  end case;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_tag_apply"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tag.tag_id, tag.subject_type, tag.subject_id;
    end if;
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."tag"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."tag"(uuid, text, text, uuid) to authenticated, service_role;

drop function if exists "better_supabase"."update_tag"(uuid, text);
drop function if exists "better_supabase"."update_tag"(uuid, text, jsonb);
-- patch: name, slug, color, description and kind to set; a key that is
-- present sets its column, so null clears color or description.
create or replace function "better_supabase"."update_tag"(tag_id uuid, name text, patch jsonb default null, fields jsonb default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = update_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if update_tag.patch is not null and (jsonb_typeof(update_tag.patch) <> 'object'
    or update_tag.patch ? 'slug' and coalesce(update_tag.patch ->> 'slug', '') !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    or update_tag.patch ? 'name' and nullif(trim(update_tag.patch ->> 'name'), '') is null
    or update_tag.patch ? 'kind' and update_tag.patch ->> 'kind' is null) then
    raise exception 'patch sets name, slug, color, description or kind; name, slug and kind can''t be empty' using errcode = '22023', hint = 'TAG_INVALID';
  end if;
  update "better_supabase"."tags" t set "name" = coalesce(update_tag.patch ->> 'name', update_tag.name, t."name"),
    "slug" = case when update_tag.patch ? 'slug' then update_tag.patch ->> 'slug' else t."slug" end,
    "color" = case when update_tag.patch ? 'color' then update_tag.patch ->> 'color' else t."color" end,
    "description" = case when update_tag.patch ? 'description' then update_tag.patch ->> 'description' else t."description" end,
    "kind" = case when update_tag.patch ? 'kind' then update_tag.patch ->> 'kind' else t."kind" end,
    "updated_at" = now() where t."id" = update_tag.tag_id;
  update "better_supabase"."tags" x set "app_note" = case when update_tag.fields ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."tags", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(update_tag.fields) e where e.key in ('app_note'))) r
  where x."id" = update_tag.tag_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."update_tag"(uuid, text, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_tag"(uuid, text, jsonb, jsonb) to authenticated, service_role;

-- Sets a tag's rank key, from rankBetween over its neighbours' keys.
create or replace function "better_supabase"."rank_tag"(tag_id uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rank_tag.rank is null or rank_tag.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'TAG_RANK_INVALID';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = rank_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  update "better_supabase"."tags" set "rank" = rank_tag.rank, "updated_at" = now() where "id" = rank_tag.tag_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_tag"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_tag"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_tag"(tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  if not found then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  delete from "better_supabase"."tags" where "id" = delete_tag.tag_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_tag"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_tag"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."untag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."taggings" g
      where g."tenant_id" = untag.tenant
        and g."tag_id" = untag.tag_id
        and g."subject_type" = untag.subject_type
        and g."subject_id" = untag.subject_id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."untag"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."untag"(uuid, text, text, uuid) to authenticated, service_role;

-- The tenant's tags of one kind (every kind when it is null), in rank order.
create or replace function "better_supabase"."list_tags"(tenant uuid, kind text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', list_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank", 'fields', jsonb_build_object('app_note', t."app_note")) order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = list_tags.tenant
      and (list_tags.kind is null or t."kind" = list_tags.kind)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_tags"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_tags"(uuid, text) to authenticated, service_role;

-- The tags on one subject, for a caller who can read the tenant's tags and the subject.
create or replace function "better_supabase"."subject_tags"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not (true) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "better_supabase"."taggings" g
      where g."tenant_id" = subject_tags.tenant
        and g."subject_type" = subject_tags.subject_type
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank", 'fields', jsonb_build_object('app_note', t."app_note")) order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."subject_tags"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."subject_tags"(uuid, text, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."tags";
create policy bsb_tenant_scope on "better_supabase"."tags" as restrictive
  for all to authenticated
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."taggings";
create policy bsb_tenant_scope on "better_supabase"."taggings" as restrictive
  for all to authenticated
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_059_tags.sql
-- better-supabase module: tags
-- @bsb-block-data tags
-- @bsb-hash sha256:baa1d5b6721528e763808c231522383a33db513a6254d0a316c15c1087308cb6
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tags', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
