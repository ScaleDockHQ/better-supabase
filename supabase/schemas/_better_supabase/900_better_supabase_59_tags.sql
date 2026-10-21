-- better-supabase module: tags
-- @bs-module tags@2 managed
-- Tenant tags with a kind, and a link from a tag to a subject. Adopt mode can use one link table per subject.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
drop function if exists "better_supabase"."create_tag"(uuid, text, text, text, text, jsonb);
create or replace function "better_supabase"."create_tag"(tenant uuid, kind text, name text, color text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_slug text := trim(both '-' from regexp_replace(lower(create_tag.name), '[^a-z0-9]+', '-', 'g'));
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to manage tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
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
  perform "better_supabase".emit_event('tag.created', jsonb_build_object('organizationId', create_tag.tenant, 'id', v_id, 'kind', create_tag.kind, 'name', create_tag.name), 'tags/' || v_id::text, (create_tag.tenant)::text, null, 'better-supabase/tags');
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank);
end;
$$;
revoke execute on function "better_supabase"."create_tag"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_tag"(uuid, text, text, text, text) to authenticated, service_role;

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
  if not (case tag.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant)
    else false
  end) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "better_supabase"."tags" where "id" = tag.tag_id and "tenant_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when 'comment' then true
    when 'company' then true
    when 'person' then true
    when 'deal' then true
    when 'engagement' then true
    when 'work_item' then true
    when 'employee' then true
    when 'product' then true
    when 'product_variant' then true
    when 'calendar_event' then true
    when 'document' then true
    when 'customer' then true
    when 'drive_node' then true
    when 'application' then true
    when 'project' then true
    when 'task' then true
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
  perform "better_supabase".emit_event('subject.tagged', jsonb_build_object('organizationId', tag.tenant, 'subjectType', tag.subject_type, 'subjectId', tag.subject_id, 'id', tag.tag_id), 'subjects/' || tag.subject_type || '/' || tag.subject_id, (tag.tenant)::text, null, 'better-supabase/tags');
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

drop function if exists "better_supabase"."update_tag"(uuid, text, jsonb);
create or replace function "better_supabase"."update_tag"(tag_id uuid, name text)
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
  update "better_supabase"."tags" t set "name" = coalesce(update_tag.name, t."name"), "updated_at" = now() where t."id" = update_tag.tag_id;
  perform "better_supabase".emit_event('tag.updated', jsonb_build_object('organizationId', v_tenant, 'id', update_tag.tag_id, 'name', update_tag.name), 'tags/' || update_tag.tag_id::text, (v_tenant)::text, null, 'better-supabase/tags');
  return true;
end;
$$;
revoke execute on function "better_supabase"."update_tag"(uuid, text) from public, anon;
grant execute on function "better_supabase"."update_tag"(uuid, text) to authenticated, service_role;

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
  perform "better_supabase".emit_event('tag.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_tag.tag_id), 'tags/' || delete_tag.tag_id::text, (v_tenant)::text, null, 'better-supabase/tags');
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
  if not (case untag.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant)
    else false
  end) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."taggings" g
      where g."tenant_id" = untag.tenant
        and g."tag_id" = untag.tag_id
        and g."subject_type" = untag.subject_type
        and g."subject_id" = untag.subject_id;
  perform "better_supabase".emit_event('subject.untagged', jsonb_build_object('organizationId', untag.tenant, 'subjectType', untag.subject_type, 'subjectId', untag.subject_id, 'id', untag.tag_id), 'subjects/' || untag.subject_type || '/' || untag.subject_id, (untag.tenant)::text, null, 'better-supabase/tags');
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
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
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
  if not (case subject_tags.subject_type
    when 'comment' then exists (select 1 from "better_supabase"."comments" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'comments.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant)
    else false
  end) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "better_supabase"."taggings" g
      where g."tenant_id" = subject_tags.tenant
        and g."subject_type" = subject_tags.subject_type
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."subject_tags"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."subject_tags"(uuid, text, text) to authenticated, service_role;

-- blocks.tags.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."create_tag"(uuid, text, text, text, text, jsonb);
drop function if exists "api"."update_tag"(uuid, text, jsonb);

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."create_tag"(tenant uuid, kind text, name text, color text, description text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_tag"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."create_tag"(uuid, text, text, text, text) from public, anon;
grant execute on function "api"."create_tag"(uuid, text, text, text, text) to authenticated, service_role;

create or replace function "api"."tag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."tag"($1, $2, $3, $4) $$;
revoke execute on function "api"."tag"(uuid, text, text, uuid) from public, anon;
grant execute on function "api"."tag"(uuid, text, text, uuid) to authenticated, service_role;

create or replace function "api"."update_tag"(tag_id uuid, name text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_tag"($1, $2) $$;
revoke execute on function "api"."update_tag"(uuid, text) from public, anon;
grant execute on function "api"."update_tag"(uuid, text) to authenticated, service_role;

create or replace function "api"."rank_tag"(tag_id uuid, rank text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."rank_tag"($1, $2) $$;
revoke execute on function "api"."rank_tag"(uuid, text) from public, anon;
grant execute on function "api"."rank_tag"(uuid, text) to authenticated, service_role;

create or replace function "api"."delete_tag"(tag_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_tag"($1) $$;
revoke execute on function "api"."delete_tag"(uuid) from public, anon;
grant execute on function "api"."delete_tag"(uuid) to authenticated, service_role;

create or replace function "api"."untag"(tenant uuid, subject_type text, subject_id text, tag_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."untag"($1, $2, $3, $4) $$;
revoke execute on function "api"."untag"(uuid, text, text, uuid) from public, anon;
grant execute on function "api"."untag"(uuid, text, text, uuid) to authenticated, service_role;

create or replace function "api"."list_tags"(tenant uuid, kind text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_tags"($1, $2) $$;
revoke execute on function "api"."list_tags"(uuid, text) from public, anon;
grant execute on function "api"."list_tags"(uuid, text) to authenticated, service_role;

create or replace function "api"."subject_tags"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_tags"($1, $2, $3) $$;
revoke execute on function "api"."subject_tags"(uuid, text, text) from public, anon;
grant execute on function "api"."subject_tags"(uuid, text, text) to authenticated, service_role;

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
