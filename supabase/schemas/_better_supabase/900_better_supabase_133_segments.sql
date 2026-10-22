-- better-supabase module: segments
-- @bsb-block segments@1 managed
-- Saved filters over a subject type, such as companies in a region or deals over a size: the matching records materialized as members, refreshed on demand or from a cron, with an event when a record enters or leaves.
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
-- Segments: a tenant's saved filter over one subject type, with materialized
-- members and events when a record enters or leaves.
create table if not exists "better_supabase"."segments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "description" text check (length("description") <= 2000),
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "conditions" jsonb not null check (jsonb_typeof("conditions") = 'object'),
  "member_count" integer not null default 0,
  "refreshed_at" timestamptz,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "name")
);
create index if not exists segments_due_idx on "better_supabase"."segments" ("refreshed_at" nulls first);
create index if not exists segments_created_by_idx on "better_supabase"."segments" ("created_by") where "created_by" is not null;
alter table "better_supabase"."segments" enable row level security;
revoke all on "better_supabase"."segments" from anon, authenticated;
grant select on "better_supabase"."segments" to authenticated;
grant all on "better_supabase"."segments" to service_role;
create table if not exists "better_supabase"."segment_members" (
  "segment_id" uuid not null references "better_supabase"."segments" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "subject_id" text not null,
  "entered_at" timestamptz not null default now(),
  primary key ("segment_id", "subject_id")
);
create index if not exists segment_members_subject_idx on "better_supabase"."segment_members" ("tenant_id", "subject_id");
alter table "better_supabase"."segment_members" enable row level security;
revoke all on "better_supabase"."segment_members" from anon, authenticated;
grant select on "better_supabase"."segment_members" to authenticated;
grant all on "better_supabase"."segment_members" to service_role;
drop policy if exists segments_read on "better_supabase"."segments";
create policy segments_read on "better_supabase"."segments" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('segments.read')));
drop policy if exists segment_members_read on "better_supabase"."segment_members";
create policy segment_members_read on "better_supabase"."segment_members" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('segments.read')));

-- Creates or changes a segment: segment is { id?, subjectType, name,
-- description?, conditions }. conditions is a FilterQuery over the rule
-- fields of the subject type, whose columns name the subject table's columns.
-- Changing the conditions clears refreshed_at, so refresh_due_segments picks
-- the segment up.
create or replace function "better_supabase"."save_segment"(tenant uuid, segment jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_old "better_supabase"."segments";
  v_row "better_supabase"."segments";
  v_type text;
  v_name text;
  v_description text;
  v_conditions jsonb;
  v_fields jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(better_supabase.can('tenant', save_segment.tenant, 'segments.edit'), false) then
    raise exception 'You need segments.edit to save a segment' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  if jsonb_typeof(segment) is distinct from 'object' then
    raise exception 'segment must be an object' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_id := nullif(segment ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."segments" x
    where x."id" = v_id and x."tenant_id" = save_segment.tenant for update;
    if v_old."id" is null then
      raise exception 'No segment in this organization has this id' using errcode = 'P0002', hint = 'SEGMENT_NOT_FOUND';
    end if;
    if segment ? 'subjectType' and segment ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'A segment''s subject type can''t change' using errcode = '22023', hint = 'SEGMENT_INVALID';
    end if;
  end if;
  v_type := coalesce(v_old."subject_type", segment ->> 'subjectType');
  if v_type is null or v_type not in ('message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'engagement', 'work_item', 'employee', 'ledger_account', 'product', 'product_variant', 'calendar_event', 'asset', 'asset_location', 'lease', 'maintenance_request', 'expense_report', 'expense_line', 'donation_fund', 'work_order', 'shipment', 'contract', 'control', 'policy', 'incident', 'document', 'customer', 'drive_node', 'application', 'project', 'task') then
    raise exception 'subjectType must be a type in config.subjects' using errcode = '22023', hint = 'SEGMENT_SUBJECT_UNKNOWN';
  end if;
  v_name := coalesce(nullif(trim(segment ->> 'name'), ''), v_old."name");
  if v_name is null or length(v_name) > 200 then
    raise exception 'A segment needs a name of at most 200 characters' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_description := case when segment ? 'description' then nullif(trim(segment ->> 'description'), '') else v_old."description" end;
  v_conditions := coalesce(segment -> 'conditions', v_old."conditions");
  if jsonb_typeof(v_conditions) is distinct from 'object' then
    raise exception 'A segment needs conditions, a filter tree' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_type);
  if v_fields = '{}'::jsonb then
    raise exception 'No rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SEGMENT_FIELDS_MISSING';
  end if;
  perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  if v_old."id" is null then
    insert into "better_supabase"."segments" ("tenant_id", "name", "description", "subject_type", "conditions", "created_by")
    values (save_segment.tenant, v_name, v_description, v_type, v_conditions, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."conditions" = v_conditions then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'conditions', v_old."conditions", 'memberCount', v_old."member_count", 'refreshedAt', v_old."refreshed_at", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at");
  else
    update "better_supabase"."segments" x set
      "name" = v_name,
      "description" = v_description,
      "conditions" = v_conditions,
      "refreshed_at" = case when x."conditions" = v_conditions then x."refreshed_at" end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('segment.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/segments');
  perform better_supabase.audit_event(
    event_type => 'segment.saved',
    category => 'data',
    target_type => 'segment',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'conditions', v_row."conditions", 'memberCount', v_row."member_count", 'refreshedAt', v_row."refreshed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'Another segment in this organization has this name' using errcode = '23505', hint = 'SEGMENT_NAME_TAKEN';
end;
$$;
revoke execute on function "better_supabase"."save_segment"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_segment"(uuid, jsonb) to authenticated, service_role;

-- Deletes a segment and its members. Members leave without segment.left.
create or replace function "better_supabase"."remove_segment"(segment uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."segments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."segments" x where x."id" = remove_segment.segment;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'segments.edit'), false)) then
    raise exception 'You need segments.edit to remove a segment' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."segments" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('segment.removed', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/segments');
  perform better_supabase.audit_event(
    event_type => 'segment.removed',
    category => 'data',
    target_type => 'segment',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_segment"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_segment"(uuid) to authenticated, service_role;

-- The organization's segments, optionally of one subject type, by name.
create or replace function "better_supabase"."segments_list"(tenant uuid, subject_type text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.can('tenant', segments_list.tenant, 'segments.read'), false) then
    raise exception 'You need segments.read to list segments' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'conditions', x."conditions", 'memberCount', x."member_count", 'refreshedAt', x."refreshed_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name")
    from "better_supabase"."segments" x
    where x."tenant_id" = segments_list.tenant
      and (segments_list.subject_type is null or x."subject_type" = segments_list.subject_type)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."segments_list"(uuid, text) from public, anon;
grant execute on function "better_supabase"."segments_list"(uuid, text) to authenticated, service_role;

create or replace function "better_supabase"."segment_get"(segment uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'conditions', x."conditions", 'memberCount', x."member_count", 'refreshedAt', x."refreshed_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."segments" x
  where x."id" = segment_get.segment and coalesce(better_supabase.can('tenant', x."tenant_id", 'segments.read'), false)
$$;
revoke execute on function "better_supabase"."segment_get"(uuid) from public, anon;
grant execute on function "better_supabase"."segment_get"(uuid) to authenticated, service_role;

-- A page of a segment's members, newest first: { subjectId, enteredAt }.
-- after is the last page's oldest enteredAt. The caller also needs the
-- subject type's read permission.
create or replace function "better_supabase"."list_segment_members"(segment uuid, after timestamptz default null, max_count integer default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."segments";
begin
  select * into v_row from "better_supabase"."segments" x where x."id" = list_segment_members.segment;
  if v_row."id" is null or not coalesce(better_supabase.can('tenant', v_row."tenant_id", 'segments.read'), false)
    or not (case v_row."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'parties.read'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'parties.read'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deals.read'), false)
    when 'course' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'courses.read'), false)
    when 'post' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.read'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'engagements.read'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'work_items.read'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'calendar.read'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.read'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.read'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shipments.read'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.read'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.read'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.read'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.read'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'documents.read'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'customers.read'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'drive.read'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.read'), false)
    else true
  end) then
    raise exception 'No segment you can read has this id' using errcode = 'P0002', hint = 'SEGMENT_NOT_FOUND';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('subjectId', y."subject_id", 'enteredAt', y."entered_at") order by y."entered_at" desc, y."subject_id")
    from (
      select z.* from "better_supabase"."segment_members" z
      where z."segment_id" = v_row."id"
        and (list_segment_members.after is null or z."entered_at" < list_segment_members.after)
      order by z."entered_at" desc, z."subject_id"
      limit least(greatest(coalesce(list_segment_members.max_count, 50), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_segment_members"(uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_segment_members"(uuid, timestamptz, integer) to authenticated, service_role;

-- The segments a record is in, among those the caller can read.
create or replace function "better_supabase"."segments_of"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'name', x."name", 'enteredAt', y."entered_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."segment_members" y
  join "better_supabase"."segments" x on x."id" = y."segment_id"
  where x."subject_type" = segments_of.subject_type and y."subject_id" = segments_of.subject_id
    and coalesce(better_supabase.can('tenant', x."tenant_id", 'segments.read'), false)
    and (case x."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'person' then coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.read'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'product' then coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'maintenance_request' then coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'document' then coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false)
    when 'application' then coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    else true
  end)
$$;
revoke execute on function "better_supabase"."segments_of"(text, text) from public, anon;
grant execute on function "better_supabase"."segments_of"(text, text) to authenticated, service_role;

-- Evaluates a segment over its subject table and stores the records that
-- match: records that start matching enter (segment.entered), records that
-- stop matching or are deleted leave (segment.left). Returns { entered,
-- left, memberCount }.
create or replace function "better_supabase"."evaluate_segment"(segment uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."segments";
  v_fields jsonb;
  v_now timestamptz := now();
  v_ids text[];
  v_entered text[];
  v_left text[];
  v_id text;
begin
  select * into v_row from "better_supabase"."segments" x where x."id" = evaluate_segment.segment for update;
  if v_row."id" is null then
    return null;
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_row."subject_type");
  if v_row."subject_type" = 'message' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."messages" s
      where s."tenant_id" = v_row."tenant_id" and s."deleted_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'conversation' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."conversations" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'channel' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."channels" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'company' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."companies" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'person' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."people" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'deal' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."deals" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'course' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."courses" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'post' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."posts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'engagement' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."engagements" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_item' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_items" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'employee' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."employees" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'ledger_account' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."ledger_accounts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'product' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."products" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'product_variant' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."product_variants" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'calendar_event' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."calendar_events" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'asset' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."assets" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'asset_location' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."asset_locations" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'lease' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."lease_agreements" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'maintenance_request' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."maintenance_requests" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'expense_report' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."expense_reports" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'expense_line' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."expense_lines" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'donation_fund' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."donation_funds" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_order' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_orders" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'shipment' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."shipments" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'contract' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."contracts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'control' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."controls" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'policy' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."policies" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'incident' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."incidents" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'document' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."documents" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'customer' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."customers" s
      where s."organization_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'drive_node' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."drive_nodes" s
      where s."tenant_id" = v_row."tenant_id" and s."deleted_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'application' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."applications" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'project' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."projects" s
      where s."organization_id" = v_row."tenant_id" and s."deleted_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'task' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."tasks" s
      where s."organization_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  else
    raise exception 'The segment''s subject type is not registered in config.subjects' using errcode = '22023', hint = 'SEGMENT_SUBJECT_UNKNOWN';
  end if;
  if cardinality(v_ids) > 10000 then
    raise exception 'A segment holds at most 10000 records; narrow its conditions' using errcode = '54000', hint = 'SEGMENT_TOO_LARGE';
  end if;
  with gone as (
    delete from "better_supabase"."segment_members" y
    where y."segment_id" = v_row."id" and not (y."subject_id" = any (v_ids))
    returning y."subject_id" as id
  ), added as (
    insert into "better_supabase"."segment_members" ("segment_id", "tenant_id", "subject_id", "entered_at")
    select v_row."id", v_row."tenant_id", z, v_now from unnest(v_ids) z
    on conflict do nothing
    returning "subject_id" as id
  )
  select coalesce((select array_agg(g.id order by g.id) from gone g), '{}'),
    coalesce((select array_agg(a.id order by a.id) from added a), '{}')
  into v_left, v_entered;
  foreach v_id in array v_entered loop
    perform "better_supabase".emit_event('segment.entered', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, 'segment.entered:' || v_row."id"::text || ':' || v_id || ':' || extract(epoch from v_now)::text, 'better-supabase/segments');
  end loop;
  foreach v_id in array v_left loop
    perform "better_supabase".emit_event('segment.left', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, 'segment.left:' || v_row."id"::text || ':' || v_id || ':' || extract(epoch from v_now)::text, 'better-supabase/segments');
  end loop;
  update "better_supabase"."segments" x set "member_count" = cardinality(v_ids), "refreshed_at" = v_now
  where x."id" = v_row."id";
  return jsonb_build_object('entered', cardinality(v_entered), 'left', cardinality(v_left), 'memberCount', cardinality(v_ids));
end;
$$;
revoke execute on function "better_supabase"."evaluate_segment"(uuid) from public, anon, authenticated;

-- Refreshes one segment now: segments.edit, or the service role.
create or replace function "better_supabase"."refresh_segment"(segment uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."segments" x where x."id" = refresh_segment.segment;
  if v_tenant is null then
    raise exception 'No segment has this id' using errcode = 'P0002', hint = 'SEGMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'segments.edit'), false)) then
    raise exception 'You need segments.edit to refresh a segment' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  return "better_supabase"."evaluate_segment"(refresh_segment.segment);
end;
$$;
revoke execute on function "better_supabase"."refresh_segment"(uuid) from public, anon;
grant execute on function "better_supabase"."refresh_segment"(uuid) to authenticated, service_role;

-- Refreshes the segments not refreshed within stale_after, oldest first, for
-- a cron. Returns { segments, entered, left }.
create or replace function "better_supabase"."refresh_due_segments"(max_count integer default null, stale_after interval default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_segment uuid;
  v_result jsonb;
  v_count integer := 0;
  v_entered integer := 0;
  v_left integer := 0;
begin
  for v_segment in
    select x."id" from "better_supabase"."segments" x
    where x."refreshed_at" is null
      or x."refreshed_at" < now() - coalesce(refresh_due_segments.stale_after, interval '1 hour')
    order by x."refreshed_at" nulls first, x."id"
    limit least(greatest(coalesce(refresh_due_segments.max_count, 25), 1), 500)
  loop
    v_result := "better_supabase"."evaluate_segment"(v_segment);
    v_count := v_count + 1;
    v_entered := v_entered + (v_result ->> 'entered')::integer;
    v_left := v_left + (v_result ->> 'left')::integer;
  end loop;
  return jsonb_build_object('segments', v_count, 'entered', v_entered, 'left', v_left);
end;
$$;
revoke execute on function "better_supabase"."refresh_due_segments"(integer, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."refresh_due_segments"(integer, interval) to service_role;

-- blocks.segments.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."save_segment"(tenant uuid, segment jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_segment"($1, $2) $$;
revoke execute on function "api"."save_segment"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_segment"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."remove_segment"(segment uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_segment"($1) $$;
revoke execute on function "api"."remove_segment"(uuid) from public, anon;
grant execute on function "api"."remove_segment"(uuid) to authenticated, service_role;

create or replace function "api"."segments_list"(tenant uuid, subject_type text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."segments_list"($1, $2) $$;
revoke execute on function "api"."segments_list"(uuid, text) from public, anon;
grant execute on function "api"."segments_list"(uuid, text) to authenticated, service_role;

create or replace function "api"."segment_get"(segment uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."segment_get"($1) $$;
revoke execute on function "api"."segment_get"(uuid) from public, anon;
grant execute on function "api"."segment_get"(uuid) to authenticated, service_role;

create or replace function "api"."list_segment_members"(segment uuid, after timestamptz default null, max_count integer default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_segment_members"($1, $2, $3) $$;
revoke execute on function "api"."list_segment_members"(uuid, timestamptz, integer) from public, anon;
grant execute on function "api"."list_segment_members"(uuid, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."segments_of"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."segments_of"($1, $2) $$;
revoke execute on function "api"."segments_of"(text, text) from public, anon;
grant execute on function "api"."segments_of"(text, text) to authenticated, service_role;

create or replace function "api"."refresh_segment"(segment uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."refresh_segment"($1) $$;
revoke execute on function "api"."refresh_segment"(uuid) from public, anon;
grant execute on function "api"."refresh_segment"(uuid) to authenticated, service_role;

create or replace function "api"."refresh_due_segments"(max_count integer default null, stale_after interval default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."refresh_due_segments"($1, $2) $$;
revoke execute on function "api"."refresh_due_segments"(integer, interval) from public, anon, authenticated;
grant execute on function "api"."refresh_due_segments"(integer, interval) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
