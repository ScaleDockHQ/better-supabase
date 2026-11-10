-- ==== schema supabase/schemas/900_better_supabase_162_dam.sql
-- better-supabase module: dam
-- @bsb-block dam@1 managed
-- @bsb-hash sha256:fc715bdc025abda1975210e76409f9623b2e5a1d7d899c7323109bc915997255
-- Renditions of drive files (thumbnails and web sizes made through the drive's preview renderers) and usage rights with a territory, a channel and an expiry date, with a reminder before a right ends.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Digital asset management on the drive: renditions of a file and the usage
-- rights that say who may use it, where and until when.

-- The derived versions of a drive file: a thumbnail, a web size. One row per
-- file and kind; the files live in storage under path.
create table "better_supabase"."dam_renditions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "node_id" uuid not null,
  "kind" text not null constraint bsb_dam_renditions_kind_check check ("kind" ~ '^[a-z][a-z0-9_]{0,40}$'),
  "status" text not null default 'ready' constraint bsb_dam_renditions_status_check check ("status" in ('pending', 'ready', 'failed')),
  "format" text constraint bsb_dam_renditions_format_check check ("format" is null or length("format") <= 20),
  "width" integer constraint bsb_dam_renditions_width_check check ("width" is null or "width" > 0),
  "height" integer constraint bsb_dam_renditions_height_check check ("height" is null or "height" > 0),
  "size_bytes" bigint constraint bsb_dam_renditions_size_bytes_check check ("size_bytes" is null or "size_bytes" >= 0),
  "path" text constraint bsb_dam_renditions_path_check check ("path" is null or length("path") <= 1000),
  "error" text constraint bsb_dam_renditions_error_check check ("error" is null or length("error") <= 500),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "node_id", "kind")
);
alter table "better_supabase"."dam_renditions" enable row level security;
revoke all on "better_supabase"."dam_renditions" from public, anon, authenticated;
grant select on "better_supabase"."dam_renditions" to authenticated;
grant all on "better_supabase"."dam_renditions" to service_role;
create policy bsb_dam_renditions_read on "better_supabase"."dam_renditions"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('dam.read')));

-- Who may use a file, where and until when. A row without territory or channel
-- covers all of them; one without expires_on never ends. A revoked right stays.
create table "better_supabase"."dam_usage_rights" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "node_id" uuid not null,
  "licensee" text not null constraint bsb_dam_usage_rights_licensee_check check (length("licensee") >= 1 and length("licensee") <= 200),
  "territory" text constraint bsb_dam_usage_rights_territory_check check ("territory" is null or length("territory") >= 1 and length("territory") <= 100),
  "channel" text constraint bsb_dam_usage_rights_channel_check check ("channel" is null or length("channel") >= 1 and length("channel") <= 100),
  "starts_on" date not null default current_date,
  "expires_on" date,
  "note" text constraint bsb_dam_usage_rights_note_check check ("note" is null or length("note") <= 2000),
  "revoked_at" timestamptz,
  -- The expiry date the reminder last went out for.
  "reminded_for" date,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_dam_usage_rights_check check ("expires_on" is null or "expires_on" >= "starts_on")
);
create index "dam_usage_rights_list_idx" on "better_supabase"."dam_usage_rights" ("tenant_id", (coalesce("expires_on", 'infinity'::date)), "id");
create index "dam_usage_rights_node_idx" on "better_supabase"."dam_usage_rights" ("tenant_id", "node_id");
create index "dam_usage_rights_expiry_idx" on "better_supabase"."dam_usage_rights" ("expires_on") where "revoked_at" is null and "expires_on" is not null;
alter table "better_supabase"."dam_usage_rights" enable row level security;
revoke all on "better_supabase"."dam_usage_rights" from public, anon, authenticated;
grant select on "better_supabase"."dam_usage_rights" to authenticated;
grant all on "better_supabase"."dam_usage_rights" to service_role;
create policy bsb_dam_usage_rights_read on "better_supabase"."dam_usage_rights"
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
  null;
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
  null;
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
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'nodeId', v_row."node_id", 'licensee', v_row."licensee", 'territory', v_row."territory", 'channel', v_row."channel", 'startsOn', v_row."starts_on", 'expiresOn', v_row."expires_on", 'status', case when v_row."revoked_at" is not null then 'revoked' when v_row."starts_on" > current_date then 'upcoming' when v_row."expires_on" is not null and v_row."expires_on" < current_date then 'expired' else 'active' end, 'note', v_row."note", 'revokedAt', v_row."revoked_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."revoke_usage_right"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_usage_right"(uuid) to authenticated, service_role;

-- Usage rights, soonest expiry first. filters is { nodeId, status: 'upcoming'
-- | 'active' | 'expired' | 'revoked', expiringWithinDays, limit, after, offset, paged, total,
-- totalCap }.
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
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_node text := nullif(v_filters ->> 'nodeId', '');
  v_status text := nullif(v_filters ->> 'status', '');
  v_expiring integer := (v_filters ->> 'expiringWithinDays')::integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_usage_rights.tenant is not null and coalesce(better_supabase.can('tenant', list_usage_rights.tenant, 'dam.read'), false))) then
    raise exception 'not allowed to read usage rights' using errcode = '42501', hint = 'DAM_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'nodeId', x."node_id", 'licensee', x."licensee", 'territory', x."territory", 'channel', x."channel", 'startsOn', x."starts_on", 'expiresOn', x."expires_on", 'status', case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end, 'note', x."note", 'revokedAt', x."revoked_at", 'createdBy', x."created_by", 'createdAt', x."created_at") as j, jsonb_build_array((coalesce(x."expires_on", 'infinity'::date))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (v_node is null or x."node_id" = v_node::uuid)
        and (v_status is null or case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end = v_status)
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
        and (v_after is null or (coalesce(x."expires_on", 'infinity'::date), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."expires_on", 'infinity'::date) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."dam_usage_rights" x
      where x."tenant_id" = list_usage_rights.tenant
        and (v_node is null or x."node_id" = v_node::uuid)
        and (v_status is null or case when x."revoked_at" is not null then 'revoked' when x."starts_on" > current_date then 'upcoming' when x."expires_on" is not null and x."expires_on" < current_date then 'expired' else 'active' end = v_status)
        and (v_expiring is null or (x."revoked_at" is null and x."expires_on" is not null and x."expires_on" between current_date and current_date + v_expiring))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
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

-- Without the notifications block there is nobody to tell; the function stays so
-- the client and its schedule work the same everywhere.
create or replace function "better_supabase"."notify_expiring_usage_rights"(days integer default 30)
returns integer
language sql
security definer
set search_path = ''
as $$ select 0 $$;
revoke execute on function "better_supabase"."notify_expiring_usage_rights"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."notify_expiring_usage_rights"(integer) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."dam_usage_rights" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('dam.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."dam_usage_rights" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."dam_usage_rights" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."dam_usage_rights" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."dam_renditions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('dam.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."dam_renditions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."dam_renditions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."dam_renditions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_162_dam.sql
-- better-supabase module: dam
-- @bsb-block-data dam
-- @bsb-hash sha256:0918b26d3a424244b1f29164f093513009377a70fd55b9a20e20010069ace602
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('dam', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
