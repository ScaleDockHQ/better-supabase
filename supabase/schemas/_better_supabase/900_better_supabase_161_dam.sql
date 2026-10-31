-- better-supabase module: dam
-- @bsb-block dam@1 managed
-- @bsb-hash sha256:8ed5755d9ca4e29fd23a5a74c9a72d9f4d4255a21873ea9e4ee1cf4ea280dc5d
-- Renditions of drive files (thumbnails and web sizes made through the drive's preview renderers) and usage rights with a territory, a channel and an expiry date, with a reminder before a right ends.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."dam_usage_rights";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."dam_usage_rights";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."dam_usage_rights";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."dam_usage_rights";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."dam_usage_rights";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."dam_renditions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."dam_renditions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."dam_renditions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."dam_renditions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."dam_renditions";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Digital asset management on the drive: renditions of a file and the usage
-- rights that say who may use it, where and until when.

-- The derived versions of a drive file: a thumbnail, a web size. One row per
-- file and kind; the files live in storage under path.
create table if not exists "better_supabase"."dam_renditions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "node_id" uuid not null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "status" text not null default 'ready' check ("status" in ('pending', 'ready', 'failed')),
  "format" text check ("format" is null or length("format") <= 20),
  "width" integer check ("width" is null or "width" > 0),
  "height" integer check ("height" is null or "height" > 0),
  "size_bytes" bigint check ("size_bytes" is null or "size_bytes" >= 0),
  "path" text check ("path" is null or length("path") <= 1000),
  "error" text check ("error" is null or length("error") <= 500),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "node_id", "kind")
);
alter table "better_supabase"."dam_renditions" enable row level security;
revoke all on "better_supabase"."dam_renditions" from public, anon, authenticated;
grant select on "better_supabase"."dam_renditions" to authenticated;
grant all on "better_supabase"."dam_renditions" to service_role;
drop policy if exists dam_renditions_read on "better_supabase"."dam_renditions";
create policy dam_renditions_read on "better_supabase"."dam_renditions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('dam.read')));

-- Who may use a file, where and until when. A row without territory or channel
-- covers all of them; one without expires_on never ends. A revoked right stays.
create table if not exists "better_supabase"."dam_usage_rights" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "node_id" uuid not null,
  "licensee" text not null check (length("licensee") between 1 and 200),
  "territory" text check ("territory" is null or length("territory") between 1 and 100),
  "channel" text check ("channel" is null or length("channel") between 1 and 100),
  "starts_on" date not null default current_date,
  "expires_on" date,
  "note" text check ("note" is null or length("note") <= 2000),
  "revoked_at" timestamptz,
  -- The expiry date the reminder last went out for.
  "reminded_for" date,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  check ("expires_on" is null or "expires_on" >= "starts_on")
);
create index if not exists "dam_usage_rights_node_idx" on "better_supabase"."dam_usage_rights" ("tenant_id", "node_id");
create index if not exists "dam_usage_rights_expiry_idx" on "better_supabase"."dam_usage_rights" ("expires_on") where "revoked_at" is null and "expires_on" is not null;
alter table "better_supabase"."dam_usage_rights" enable row level security;
revoke all on "better_supabase"."dam_usage_rights" from public, anon, authenticated;
grant select on "better_supabase"."dam_usage_rights" to authenticated;
grant all on "better_supabase"."dam_usage_rights" to service_role;
drop policy if exists dam_usage_rights_read on "better_supabase"."dam_usage_rights";
create policy dam_usage_rights_read on "better_supabase"."dam_usage_rights"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('dam.read')));


-- Records one rendition of a file, replacing the one of the same kind. input
-- is { status: 'pending' | 'ready' | 'failed', format, width, height,
-- sizeBytes, path, error }. A renderer job calls it as the service role, a
-- member needs dam.write.
create or replace function "better_supabase"."record_rendition"(tenant uuid, node_id uuid, kind text, input jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."dam_renditions";
  v_input jsonb := coalesce(record_rendition.input, '{}'::jsonb);
  v_status text := coalesce(nullif(v_input ->> 'status', ''), 'ready');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (record_rendition.tenant is not null and coalesce(better_supabase.can('tenant', record_rendition.tenant, 'dam.write'), false))) then
    raise exception 'not allowed to record renditions' using errcode = '42501', hint = 'DAM_FORBIDDEN';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  if record_rendition.kind is null or record_rendition.kind !~ '^[a-z][a-z0-9_]{0,40}$' then
    raise exception 'a rendition kind is lowercase letters, digits and underscores, up to 41 characters' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  if v_status not in ('pending', 'ready', 'failed') then
    raise exception 'the status is pending, ready or failed' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  begin
    insert into "better_supabase"."dam_renditions" ("tenant_id", "node_id", "kind", "status", "format", "width", "height", "size_bytes", "path", "error")
    values (record_rendition.tenant, record_rendition.node_id, record_rendition.kind, v_status,
      nullif(v_input ->> 'format', ''), (v_input ->> 'width')::integer, (v_input ->> 'height')::integer,
      (v_input ->> 'sizeBytes')::bigint, nullif(v_input ->> 'path', ''), nullif(v_input ->> 'error', ''))
    on conflict ("tenant_id", "node_id", "kind") do update set
      "status" = excluded."status", "format" = excluded."format", "width" = excluded."width",
      "height" = excluded."height", "size_bytes" = excluded."size_bytes", "path" = excluded."path",
      "error" = excluded."error", "updated_at" = now()
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'a rendition has a format of up to 20 characters, a width and height above 0, a size of 0 or more and a path of up to 1000 characters' using errcode = '22023', hint = 'DAM_INVALID';
  end;
  perform "better_supabase".emit_event('dam_rendition.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'nodeId', v_row."node_id", 'kind', v_row."kind", 'status', v_row."status"), 'dam-renditions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dam');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'nodeId', v_row."node_id", 'kind', v_row."kind", 'status', v_row."status", 'format', v_row."format", 'width', v_row."width", 'height', v_row."height", 'sizeBytes', v_row."size_bytes", 'path', v_row."path", 'error', v_row."error", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."record_rendition"(uuid, uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."record_rendition"(uuid, uuid, text, jsonb) to authenticated, service_role;

-- The renditions of a file, by kind.
create or replace function "better_supabase"."list_renditions"(tenant uuid, node_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_renditions.tenant is not null and coalesce(better_supabase.can('tenant', list_renditions.tenant, 'dam.read'), false))) then
    raise exception 'not allowed to read renditions' using errcode = '42501', hint = 'DAM_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'nodeId', x."node_id", 'kind', x."kind", 'status', x."status", 'format', x."format", 'width', x."width", 'height', x."height", 'sizeBytes', x."size_bytes", 'path', x."path", 'error', x."error", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."kind")
    from "better_supabase"."dam_renditions" x
    where x."tenant_id" = list_renditions.tenant and x."node_id" = list_renditions.node_id
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_renditions"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."list_renditions"(uuid, uuid) to authenticated, service_role;

-- Grants a usage right on a file. input is { nodeId, licensee, territory,
-- channel, startsOn, expiresOn, note }. A right without territory or channel
-- covers every territory or channel; without expiresOn it never expires.
-- Needs dam.write.
create or replace function "better_supabase"."grant_usage_right"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."dam_usage_rights";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (grant_usage_right.tenant is not null and coalesce(better_supabase.can('tenant', grant_usage_right.tenant, 'dam.write'), false))) then
    raise exception 'not allowed to grant usage rights' using errcode = '42501', hint = 'DAM_FORBIDDEN';
  end if;
  if jsonb_typeof(grant_usage_right.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_dam_usage_right_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using grant_usage_right.tenant, grant_usage_right.input;
    end if;
  end;
  begin
    insert into "better_supabase"."dam_usage_rights" ("tenant_id", "node_id", "licensee", "territory", "channel", "starts_on", "expires_on", "note", "created_by")
    values (grant_usage_right.tenant, (grant_usage_right.input ->> 'nodeId')::uuid, trim(grant_usage_right.input ->> 'licensee'),
      nullif(trim(grant_usage_right.input ->> 'territory'), ''), nullif(trim(grant_usage_right.input ->> 'channel'), ''),
      coalesce((grant_usage_right.input ->> 'startsOn')::date, current_date), (grant_usage_right.input ->> 'expiresOn')::date,
      nullif(trim(grant_usage_right.input ->> 'note'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'a usage right needs a nodeId, a licensee of 1 to 200 characters and an expiresOn on or after startsOn' using errcode = '22023', hint = 'DAM_INVALID';
  end;
  perform "better_supabase".emit_event('dam_usage_right.granted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'nodeId', v_row."node_id", 'licensee', v_row."licensee", 'expiresOn', v_row."expires_on"), 'dam-usage-rights/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dam');
  perform better_supabase.audit_event(
    event_type => 'dam_usage_right.granted',
    category => 'data',
    target_type => 'dam_usage_right',
    record_id => v_row."id"::text,
    target_label => v_row."licensee",
    summary => 'usage right granted',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'nodeId', v_row."node_id", 'licensee', v_row."licensee", 'expiresOn', v_row."expires_on")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_dam_usage_right_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'nodeId', v_row."node_id", 'licensee', v_row."licensee", 'territory', v_row."territory", 'channel', v_row."channel", 'startsOn', v_row."starts_on", 'expiresOn', v_row."expires_on", 'status', case when v_row."revoked_at" is not null then 'revoked' when v_row."starts_on" > current_date then 'upcoming' when v_row."expires_on" is not null and v_row."expires_on" < current_date then 'expired' else 'active' end, 'note', v_row."note", 'revokedAt', v_row."revoked_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."grant_usage_right"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."grant_usage_right"(uuid, jsonb) to authenticated, service_role;

-- Revokes a usage right. It stays in the history as revoked. Needs dam.write.
create or replace function "better_supabase"."revoke_usage_right"(right_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."dam_usage_rights";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."dam_usage_rights" x where x."id" = revoke_usage_right.right_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dam.read'), false))) then
    raise exception 'no such usage right' using errcode = 'P0002', hint = 'DAM_USAGE_RIGHT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dam.write'), false))) then
    raise exception 'not allowed to revoke usage rights' using errcode = '42501', hint = 'DAM_FORBIDDEN';
  end if;
  if v_row."revoked_at" is null then
    update "better_supabase"."dam_usage_rights" x set "revoked_at" = now() where x."id" = v_row."id" returning * into v_row;
    perform "better_supabase".emit_event('dam_usage_right.revoked', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'nodeId', v_row."node_id", 'licensee', v_row."licensee", 'expiresOn', v_row."expires_on"), 'dam-usage-rights/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dam');
  perform better_supabase.audit_event(
    event_type => 'dam_usage_right.revoked',
    category => 'data',
    target_type => 'dam_usage_right',
    record_id => v_row."id"::text,
    target_label => v_row."licensee",
    summary => 'usage right revoked',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'nodeId', v_row."node_id", 'licensee', v_row."licensee", 'expiresOn', v_row."expires_on")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'nodeId', v_row."node_id", 'licensee', v_row."licensee", 'territory', v_row."territory", 'channel', v_row."channel", 'startsOn', v_row."starts_on", 'expiresOn', v_row."expires_on", 'status', case when v_row."revoked_at" is not null then 'revoked' when v_row."starts_on" > current_date then 'upcoming' when v_row."expires_on" is not null and v_row."expires_on" < current_date then 'expired' else 'active' end, 'note', v_row."note", 'revokedAt', v_row."revoked_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."revoke_usage_right"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_usage_right"(uuid) to authenticated, service_role;

-- Usage rights, soonest expiry first. filters is { nodeId, status: 'upcoming'
-- | 'active' | 'expired' | 'revoked', expiringWithinDays, limit, offset }.
create or replace function "better_supabase"."list_usage_rights"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_usage_rights.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_usage_rights.tenant is not null and coalesce(better_supabase.can('tenant', list_usage_rights.tenant, 'dam.read'), false))) then
    raise exception 'not allowed to read usage rights' using errcode = '42501', hint = 'DAM_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'nodeId', y."node_id", 'licensee', y."licensee", 'territory', y."territory", 'channel', y."channel", 'startsOn', y."starts_on", 'expiresOn', y."expires_on", 'status', case when y."revoked_at" is not null then 'revoked' when y."starts_on" > current_date then 'upcoming' when y."expires_on" is not null and y."expires_on" < current_date then 'expired' else 'active' end, 'note', y."note", 'revokedAt', y."revoked_at", 'createdBy', y."created_by", 'createdAt', y."created_at") order by y."expires_on" nulls last, y."id")
    from (
      select * from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (not v_filters ? 'nodeId' or x."node_id" = (v_filters ->> 'nodeId')::uuid)
        and (not v_filters ? 'status' or case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end = v_filters ->> 'status')
        and (not v_filters ? 'expiringWithinDays' or (
          x."revoked_at" is null and x."expires_on" is not null
          and x."expires_on" between current_date and current_date + (v_filters ->> 'expiringWithinDays')::integer
        ))
      order by x."expires_on" nulls last, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_usage_rights"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_usage_rights"(uuid, jsonb) to authenticated, service_role;

-- Whether a file may be used. filters is { on, territory, channel }: a right
-- that is active that day and names that territory and channel, or names none,
-- allows it. Returns { allowed, rightId, expiresOn }. A file without any
-- right is not allowed.
create or replace function "better_supabase"."check_usage"(tenant uuid, node_id uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(check_usage.filters, '{}'::jsonb);
  v_day date := coalesce((v_filters ->> 'on')::date, current_date);
  v_row "better_supabase"."dam_usage_rights";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (check_usage.tenant is not null and coalesce(better_supabase.can('tenant', check_usage.tenant, 'dam.read'), false))) then
    raise exception 'not allowed to read usage rights' using errcode = '42501', hint = 'DAM_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."dam_usage_rights" x
  where x."tenant_id" = check_usage.tenant and x."node_id" = check_usage.node_id
    and case when x."revoked_at" is not null then 'revoked' when x."starts_on" > v_day then 'upcoming' when x."expires_on" is not null and x."expires_on" < v_day then 'expired' else 'active' end = 'active'
    and (x."territory" is null or x."territory" = v_filters ->> 'territory')
    and (x."channel" is null or x."channel" = v_filters ->> 'channel')
  order by x."expires_on" desc nulls first, x."id"
  limit 1;
  if not found then
    return jsonb_build_object('allowed', false, 'rightId', null, 'expiresOn', null);
  end if;
  return jsonb_build_object('allowed', true, 'rightId', v_row."id", 'expiresOn', v_row."expires_on");
end;
$$;
revoke execute on function "better_supabase"."check_usage"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."check_usage"(uuid, uuid, jsonb) to authenticated, service_role;

-- Tells the member who granted a right that it ends within days days, once per
-- expiry date (changing the date allows a new notice). Run it daily from a job.
-- Returns how many rights it reported.
create or replace function "better_supabase"."notify_expiring_usage_rights"(days integer default 30)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."dam_usage_rights";
  v_claims text;
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."dam_usage_rights" x
    where x."revoked_at" is null and x."expires_on" is not null
      and x."expires_on" between current_date and current_date + greatest(notify_expiring_usage_rights.days, 0)
      and x."reminded_for" is distinct from x."expires_on"
    for update skip locked
  loop
    if v_row."created_by" is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'dam_usage_right.expiry_notified',
        'tenant', v_row."tenant_id",
        'actor', null,
        'subject_type', 'dam_usage_right',
        'subject_id', v_row."id"::text,
        'summary', v_row."licensee",
        'recipients', to_jsonb(array[v_row."created_by"]),
        'key', 'dam_usage_right.expiry_notified:' || v_row."id"::text || ':' || v_row."expires_on"::text,
        'data', jsonb_build_object('usageRightId', v_row."id", 'nodeId', v_row."node_id", 'expiresOn', v_row."expires_on")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."dam_usage_rights" x set "reminded_for" = v_row."expires_on" where x."id" = v_row."id";
    perform "better_supabase".emit_event('dam_usage_right.expiry_notified', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'nodeId', v_row."node_id", 'licensee', v_row."licensee", 'expiresOn', v_row."expires_on"), 'dam-usage-rights/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dam');
  perform better_supabase.audit_event(
    event_type => 'dam_usage_right.expiry_notified',
    category => 'data',
    target_type => 'dam_usage_right',
    record_id => v_row."id"::text,
    target_label => v_row."licensee",
    summary => 'usage right expires soon',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'nodeId', v_row."node_id", 'licensee', v_row."licensee", 'expiresOn', v_row."expires_on")
  );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."notify_expiring_usage_rights"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."notify_expiring_usage_rights"(integer) to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."dam_usage_rights";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."dam_usage_rights";
create policy bsb_tenant_scope_select on "better_supabase"."dam_usage_rights" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('dam.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."dam_usage_rights";
create policy bsb_tenant_scope_insert on "better_supabase"."dam_usage_rights" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."dam_usage_rights";
create policy bsb_tenant_scope_update on "better_supabase"."dam_usage_rights" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."dam_usage_rights";
create policy bsb_tenant_scope_delete on "better_supabase"."dam_usage_rights" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."dam_renditions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."dam_renditions";
create policy bsb_tenant_scope_select on "better_supabase"."dam_renditions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('dam.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."dam_renditions";
create policy bsb_tenant_scope_insert on "better_supabase"."dam_renditions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."dam_renditions";
create policy bsb_tenant_scope_update on "better_supabase"."dam_renditions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."dam_renditions";
create policy bsb_tenant_scope_delete on "better_supabase"."dam_renditions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.dam.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."import_run"()
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_run"() $$;
revoke execute on function "api"."import_run"() from public;
grant execute on function "api"."import_run"() to anon, authenticated, service_role;

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

create or replace function "api"."record_rendition"(tenant uuid, node_id uuid, kind text, input jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_rendition"($1, $2, $3, $4) $$;
revoke execute on function "api"."record_rendition"(uuid, uuid, text, jsonb) from public, anon;
grant execute on function "api"."record_rendition"(uuid, uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."list_renditions"(tenant uuid, node_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_renditions"($1, $2) $$;
revoke execute on function "api"."list_renditions"(uuid, uuid) from public, anon;
grant execute on function "api"."list_renditions"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."grant_usage_right"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."grant_usage_right"($1, $2) $$;
revoke execute on function "api"."grant_usage_right"(uuid, jsonb) from public, anon;
grant execute on function "api"."grant_usage_right"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."revoke_usage_right"(right_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revoke_usage_right"($1) $$;
revoke execute on function "api"."revoke_usage_right"(uuid) from public, anon;
grant execute on function "api"."revoke_usage_right"(uuid) to authenticated, service_role;

create or replace function "api"."list_usage_rights"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_usage_rights"($1, $2) $$;
revoke execute on function "api"."list_usage_rights"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_usage_rights"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."check_usage"(tenant uuid, node_id uuid, filters jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."check_usage"($1, $2, $3) $$;
revoke execute on function "api"."check_usage"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."check_usage"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."notify_expiring_usage_rights"(days integer default 30)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."notify_expiring_usage_rights"($1) $$;
revoke execute on function "api"."notify_expiring_usage_rights"(integer) from public, anon, authenticated;
grant execute on function "api"."notify_expiring_usage_rights"(integer) to service_role;

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
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
