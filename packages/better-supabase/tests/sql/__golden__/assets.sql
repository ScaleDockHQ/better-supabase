-- ==== alone: schema supabase/schemas/900_better_supabase_113_assets.sql
-- better-supabase module: assets
-- @bs-module assets@1 managed
-- A location hierarchy (site, building, unit) and an asset registry with tags, status, coordinates and assignment to members or records. Optional PostGIS stores points and areas as geography; bookings resources and work items can name an asset.
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
create table if not exists "better_supabase"."asset_locations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid references "better_supabase"."asset_locations" ("id") on delete restrict,
  -- site, building, floor, unit, room, or the app's own kind.
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "code" text check ("code" is null or length("code") between 1 and 100),
  "address" jsonb not null default '{}'::jsonb check (jsonb_typeof("address") = 'object'),
  "latitude" double precision check ("latitude" between -90 and 90),
  "longitude" double precision check ("longitude" between -180 and 180),
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  check (("latitude" is null) = ("longitude" is null))
);
create index if not exists "asset_locations_parent_idx" on "better_supabase"."asset_locations" ("tenant_id", "parent_id");
create index if not exists "asset_locations_coordinates_idx" on "better_supabase"."asset_locations" ("tenant_id", "latitude", "longitude") where "latitude" is not null;

create table if not exists "better_supabase"."assets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid references "better_supabase"."asset_locations" ("id") on delete set null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  -- The asset tag, unique per organization.
  "tag" text check ("tag" is null or length("tag") between 1 and 100),
  "serial_number" text check ("serial_number" is null or length("serial_number") <= 200),
  "status" text not null default 'active' check ("status" in ('active', 'maintenance', 'retired')),
  -- member (a user id) or a subject type such as party, with its id.
  "assignee_type" text check ("assignee_type" is null or "assignee_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "assignee_id" text,
  -- Where a moving asset (a vehicle) was last seen.
  "latitude" double precision check ("latitude" between -90 and 90),
  "longitude" double precision check ("longitude" between -180 and 180),
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "retired_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "tag"),
  check (("assignee_type" is null) = ("assignee_id" is null)),
  check (("latitude" is null) = ("longitude" is null))
);
create index if not exists "assets_location_idx" on "better_supabase"."assets" ("tenant_id", "location_id");
create index if not exists "assets_assignee_idx" on "better_supabase"."assets" ("tenant_id", "assignee_type", "assignee_id") where "assignee_type" is not null;
create index if not exists "assets_kind_idx" on "better_supabase"."assets" ("tenant_id", "kind", "status");
create index if not exists "assets_coordinates_idx" on "better_supabase"."assets" ("tenant_id", "latitude", "longitude") where "latitude" is not null;

create table if not exists "better_supabase"."asset_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "asset_id" uuid not null references "better_supabase"."assets" ("id") on delete cascade,
  "assignee_type" text not null,
  "assignee_id" text not null,
  "note" text check ("note" is null or length("note") <= 2000),
  "assigned_by" uuid,
  "assigned_at" timestamptz not null default now(),
  "released_at" timestamptz
);
create unique index if not exists "asset_assignments_open_idx" on "better_supabase"."asset_assignments" ("asset_id") where "released_at" is null;
create index if not exists "asset_assignments_history_idx" on "better_supabase"."asset_assignments" ("asset_id", "assigned_at" desc);

alter table "better_supabase"."asset_locations" enable row level security;
revoke all on "better_supabase"."asset_locations" from anon, authenticated;
grant select on "better_supabase"."asset_locations" to authenticated;
grant all on "better_supabase"."asset_locations" to service_role;
drop policy if exists "asset_locations_read" on "better_supabase"."asset_locations";
create policy "asset_locations_read" on "better_supabase"."asset_locations" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));
alter table "better_supabase"."assets" enable row level security;
revoke all on "better_supabase"."assets" from anon, authenticated;
grant select on "better_supabase"."assets" to authenticated;
grant all on "better_supabase"."assets" to service_role;
drop policy if exists "assets_read" on "better_supabase"."assets";
create policy "assets_read" on "better_supabase"."assets" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text));
alter table "better_supabase"."asset_assignments" enable row level security;
revoke all on "better_supabase"."asset_assignments" from anon, authenticated;
grant select on "better_supabase"."asset_assignments" to authenticated;
grant all on "better_supabase"."asset_assignments" to service_role;
drop policy if exists "asset_assignments_read" on "better_supabase"."asset_assignments";
create policy "asset_assignments_read" on "better_supabase"."asset_assignments" for select to authenticated
  using ("asset_id" in (select y."id" from "better_supabase"."assets" y));

-- A location's parent is in the same organization and never one of its own
-- descendants, so the hierarchy stays a tree.
create or replace function "better_supabase"."asset_location_check_parent"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."parent_id" is null then
    return new;
  end if;
  if not exists (
    select 1 from "better_supabase"."asset_locations" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id"
  ) then
    raise exception 'the parent location doesn''t exist in this organization' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if tg_op = 'UPDATE' and exists (
    with recursive up as (
      select x."id" as id, x."parent_id" as parent, 1 as depth from "better_supabase"."asset_locations" x where x."id" = new."parent_id"
      union all
      select x."id", x."parent_id", up.depth + 1 from "better_supabase"."asset_locations" x join up on x."id" = up.parent where up.depth < 64
    )
    select 1 from up where up.id = new."id"
  ) then
    raise exception 'a location can''t be inside one of its own sublocations' using errcode = '23514', hint = 'ASSETS_LOCATION_CYCLE';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."asset_location_check_parent"() from public, anon, authenticated;
drop trigger if exists "bs_asset_locations_parent" on "better_supabase"."asset_locations";
create trigger "bs_asset_locations_parent" before insert or update of "parent_id" on "better_supabase"."asset_locations"
  for each row execute function "better_supabase"."asset_location_check_parent"();


-- Adds a location (a site, building, floor, unit or room) under parent_id,
-- or at the top when it is null. area is GeoJSON and needs the postgis option.
create or replace function "better_supabase"."create_asset_location"(tenant uuid, kind text, name text, parent_id uuid default null, code text default null, address jsonb default null, latitude double precision default null, longitude double precision default null, area jsonb default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_asset_location.tenant, 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if create_asset_location.area is not null then
    raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
  end if;
  if create_asset_location.code is not null and exists (
    select 1 from "better_supabase"."asset_locations" x where x."tenant_id" = create_asset_location.tenant and x."code" = create_asset_location.code
  ) then
    raise exception 'a location with this code already exists' using errcode = '23505', hint = 'ASSETS_CODE_TAKEN';
  end if;
  insert into "better_supabase"."asset_locations" ("tenant_id", "parent_id", "kind", "name", "code", "address", "latitude", "longitude", "metadata")
  values (create_asset_location.tenant, create_asset_location.parent_id, create_asset_location.kind, trim(create_asset_location.name),
    create_asset_location.code, coalesce(create_asset_location.address, '{}'::jsonb), create_asset_location.latitude,
    create_asset_location.longitude, coalesce(create_asset_location.metadata, '{}'::jsonb))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_asset_location"(uuid, text, text, uuid, text, jsonb, double precision, double precision, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_asset_location"(uuid, text, text, uuid, text, jsonb, double precision, double precision, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, parentId, code, address,
-- latitude, longitude, area and metadata. A null value clears an optional key.
create or replace function "better_supabase"."update_asset_location"(location_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."asset_locations" x where x."id" = update_asset_location.location_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_asset_location.patch) is distinct from 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'ASSETS_PATCH_INVALID';
  end if;
  if update_asset_location.patch ? 'area' and jsonb_typeof(update_asset_location.patch -> 'area') <> 'null' then
    raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
  end if;
  if update_asset_location.patch ? 'code' and update_asset_location.patch ->> 'code' is not null and exists (
    select 1 from "better_supabase"."asset_locations" x where x."tenant_id" = v_row."tenant_id" and x."code" = update_asset_location.patch ->> 'code' and x."id" <> v_row."id"
  ) then
    raise exception 'a location with this code already exists' using errcode = '23505', hint = 'ASSETS_CODE_TAKEN';
  end if;
  update "better_supabase"."asset_locations" x set
    "kind" = case when update_asset_location.patch ? 'kind' then update_asset_location.patch ->> 'kind' else x."kind" end,
    "name" = case when update_asset_location.patch ? 'name' then trim(update_asset_location.patch ->> 'name') else x."name" end,
    "parent_id" = case when update_asset_location.patch ? 'parentId' then (update_asset_location.patch ->> 'parentId')::uuid else x."parent_id" end,
    "code" = case when update_asset_location.patch ? 'code' then update_asset_location.patch ->> 'code' else x."code" end,
    "address" = case when update_asset_location.patch ? 'address' then coalesce(nullif(update_asset_location.patch -> 'address', 'null'::jsonb), '{}'::jsonb) else x."address" end,
    "latitude" = case when update_asset_location.patch ? 'latitude' then (update_asset_location.patch ->> 'latitude')::double precision else x."latitude" end,
    "longitude" = case when update_asset_location.patch ? 'longitude' then (update_asset_location.patch ->> 'longitude')::double precision else x."longitude" end,
    "metadata" = case when update_asset_location.patch ? 'metadata' then coalesce(nullif(update_asset_location.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x."metadata" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_asset_location"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_asset_location"(uuid, jsonb) to authenticated, service_role;

-- Archives a location with no open sublocations and no assets in service.
create or replace function "better_supabase"."archive_asset_location"(location_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."asset_locations" x where x."id" = archive_asset_location.location_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."asset_locations" y where y."parent_id" = v_row."id" and y."archived_at" is null)
    or exists (select 1 from "better_supabase"."assets" y where y."location_id" = v_row."id" and y."status" <> 'retired') then
    raise exception 'move or archive the sublocations and assets of this location first' using errcode = '55000', hint = 'ASSETS_LOCATION_IN_USE';
  end if;
  if v_row."archived_at" is null then
    update "better_supabase"."asset_locations" x set "archived_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_asset_location"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_asset_location"(uuid) to authenticated, service_role;

-- A location with its path from the top (path ends with the location itself)
-- and how many sublocations and assets it holds.
create or replace function "better_supabase"."get_asset_location"(location_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  select * into v_row from "better_supabase"."asset_locations" x where x."id" = get_asset_location.location_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'path', coalesce((
    with recursive up as (
      select y."id" as id, y."parent_id" as parent, y."kind" as kind, y."name" as name, 0 as depth from "better_supabase"."asset_locations" y where y."id" = v_row."id"
      union all
      select y."id", y."parent_id", y."kind", y."name", up.depth + 1 from "better_supabase"."asset_locations" y join up on y."id" = up.parent where up.depth < 64
    )
    select jsonb_agg(jsonb_build_object('id', up.id, 'kind', up.kind, 'name', up.name) order by up.depth desc) from up
  ), '[]'::jsonb),
    'locations', (select count(*)::integer from "better_supabase"."asset_locations" y where y."parent_id" = v_row."id" and y."archived_at" is null),
    'assets', (select count(*)::integer from "better_supabase"."assets" y where y."location_id" = v_row."id" and y."status" <> 'retired'));
end;
$$;
revoke execute on function "better_supabase"."get_asset_location"(uuid) from public, anon;
grant execute on function "better_supabase"."get_asset_location"(uuid) to authenticated, service_role;

-- The locations directly under parent_id, or the top ones when it is null.
create or replace function "better_supabase"."list_asset_locations"(tenant uuid, parent_id uuid default null, include_archived boolean default false, page_size integer default 200)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.name, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'parentId', x."parent_id", 'kind', x."kind", 'name', x."name", 'code', x."code", 'address', x."address", 'latitude', x."latitude", 'longitude', x."longitude", 'area', null::jsonb, 'metadata', x."metadata", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."name" as name, x."id" as id
    from "better_supabase"."asset_locations" x
    where x."tenant_id" = list_asset_locations.tenant
      and x."parent_id" is not distinct from list_asset_locations.parent_id
      and (coalesce(list_asset_locations.include_archived, false) or x."archived_at" is null)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false))
    order by x."name", x."id"
    limit least(greatest(coalesce(list_asset_locations.page_size, 200), 1), 1000)
  ) z
$$;
revoke execute on function "better_supabase"."list_asset_locations"(uuid, uuid, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_asset_locations"(uuid, uuid, boolean, integer) to authenticated, service_role;

-- Registers an asset, at location_id when given.
create or replace function "better_supabase"."create_asset"(tenant uuid, kind text, name text, location_id uuid default null, tag text default null, serial_number text default null, latitude double precision default null, longitude double precision default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_asset.tenant, 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if create_asset.location_id is not null and not exists (
    select 1 from "better_supabase"."asset_locations" y where y."id" = create_asset.location_id and y."tenant_id" = create_asset.tenant and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if create_asset.tag is not null and exists (
    select 1 from "better_supabase"."assets" x where x."tenant_id" = create_asset.tenant and x."tag" = create_asset.tag
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  insert into "better_supabase"."assets" ("tenant_id", "location_id", "kind", "name", "tag", "serial_number", "latitude", "longitude", "metadata", "created_by")
  values (create_asset.tenant, create_asset.location_id, create_asset.kind, trim(create_asset.name), create_asset.tag,
    create_asset.serial_number, create_asset.latitude, create_asset.longitude, coalesce(create_asset.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) from public, anon;
grant execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, locationId, tag, serialNumber,
-- status, latitude, longitude and metadata. Retiring an asset releases it.
create or replace function "better_supabase"."update_asset"(asset_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
  v_location uuid;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = update_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_asset.patch) is distinct from 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'ASSETS_PATCH_INVALID';
  end if;
  v_location := case when update_asset.patch ? 'locationId' then (update_asset.patch ->> 'locationId')::uuid else v_row."location_id" end;
  if v_location is distinct from v_row."location_id" then
    if v_location is not null and not exists (
    select 1 from "better_supabase"."asset_locations" y where y."id" = v_location and y."tenant_id" = v_row."tenant_id" and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  end if;
  v_status := case when update_asset.patch ? 'status' then update_asset.patch ->> 'status' else v_row."status" end;
  if update_asset.patch ? 'tag' and update_asset.patch ->> 'tag' is not null and exists (
    select 1 from "better_supabase"."assets" x where x."tenant_id" = v_row."tenant_id" and x."tag" = update_asset.patch ->> 'tag' and x."id" <> v_row."id"
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  if v_status = 'retired' and v_row."status" <> 'retired' then
    update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  end if;
  update "better_supabase"."assets" x set
    "kind" = case when update_asset.patch ? 'kind' then update_asset.patch ->> 'kind' else x."kind" end,
    "name" = case when update_asset.patch ? 'name' then trim(update_asset.patch ->> 'name') else x."name" end,
    "location_id" = v_location,
    "tag" = case when update_asset.patch ? 'tag' then update_asset.patch ->> 'tag' else x."tag" end,
    "serial_number" = case when update_asset.patch ? 'serialNumber' then update_asset.patch ->> 'serialNumber' else x."serial_number" end,
    "status" = v_status,
    "latitude" = case when update_asset.patch ? 'latitude' then (update_asset.patch ->> 'latitude')::double precision else x."latitude" end,
    "longitude" = case when update_asset.patch ? 'longitude' then (update_asset.patch ->> 'longitude')::double precision else x."longitude" end,
    "metadata" = case when update_asset.patch ? 'metadata' then coalesce(nullif(update_asset.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x."metadata" end,
    "assignee_type" = case when v_status = 'retired' then null else x."assignee_type" end,
    "assignee_id" = case when v_status = 'retired' then null else x."assignee_id" end,
    "retired_at" = case when v_status = 'retired' then coalesce(x."retired_at", now()) else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_asset"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_asset"(uuid, jsonb) to authenticated, service_role;

-- Assigns an asset to a member (assignee_type member, a user id) or to a
-- record such as a party. The previous assignment ends.
create or replace function "better_supabase"."assign_asset"(asset_id uuid, assignee_type text, assignee_id text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = assign_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."status" = 'retired' then
    raise exception 'a retired asset can''t be assigned' using errcode = '55000', hint = 'ASSETS_RETIRED';
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
    raise exception 'an assignee needs a lowercase type and an id' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  if assign_asset.assignee_type = 'member' and (
    assign_asset.assignee_id !~ '^[0-9a-fA-F-]{36}$'
    or not coalesce(better_supabase.can_user(assign_asset.assignee_id::uuid, 'tenant', v_row."tenant_id", 'assets.read'), false)
  ) then
    raise exception 'the member can''t see this organization''s assets' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_asset_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using v_row."id", assign_asset.assignee_type, assign_asset.assignee_id;
    end if;
  end;
  update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  insert into "better_supabase"."asset_assignments" ("tenant_id", "asset_id", "assignee_type", "assignee_id", "note", "assigned_by")
  values (v_row."tenant_id", v_row."id", assign_asset.assignee_type, assign_asset.assignee_id, nullif(trim(assign_asset.note), ''), auth.uid());
  update "better_supabase"."assets" x set "assignee_type" = assign_asset.assignee_type, "assignee_id" = assign_asset.assignee_id, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_asset_assign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."assign_asset"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."assign_asset"(uuid, text, text, text) to authenticated, service_role;

-- Ends the asset's current assignment; a no-op when it has none.
create or replace function "better_supabase"."release_asset"(asset_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = release_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."assignee_type" is not null then
    update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
    update "better_supabase"."assets" x set "assignee_type" = null, "assignee_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."release_asset"(uuid) from public, anon;
grant execute on function "better_supabase"."release_asset"(uuid) to authenticated, service_role;

-- An asset with its location's path and the booking resources and open work
-- items that name it.
create or replace function "better_supabase"."get_asset"(asset_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  select * into v_row from "better_supabase"."assets" x where x."id" = get_asset.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'locationPath', case when v_row."location_id" is null then '[]'::jsonb else coalesce((
    with recursive up as (
      select y."id" as id, y."parent_id" as parent, y."kind" as kind, y."name" as name, 0 as depth from "better_supabase"."asset_locations" y where y."id" = v_row."location_id"
      union all
      select y."id", y."parent_id", y."kind", y."name", up.depth + 1 from "better_supabase"."asset_locations" y join up on y."id" = up.parent where up.depth < 64
    )
    select jsonb_agg(jsonb_build_object('id', up.id, 'kind', up.kind, 'name', up.name) order by up.depth desc) from up
  ), '[]'::jsonb) end,
    'links', jsonb_build_object('bookingResources', '[]'::jsonb, 'workItems', '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_asset"(uuid) from public, anon;
grant execute on function "better_supabase"."get_asset"(uuid) to authenticated, service_role;

-- Assets newest first. With location_id, include_sublocations also returns
-- the assets below it. With tenant null an assignee decides the organization.
create or replace function "better_supabase"."list_assets"(tenant uuid, location_id uuid default null, include_sublocations boolean default false, kind text default null, status text default null, assignee_type text default null, assignee_id text default null, query text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with recursive below as (
    select y."id" as id, 0 as depth from "better_supabase"."asset_locations" y where y."id" = list_assets.location_id
    union all
    select y."id", below.depth + 1 from "better_supabase"."asset_locations" y join below on y."parent_id" = below.id
    where coalesce(list_assets.include_sublocations, false) and below.depth < 64
  )
  select coalesce(jsonb_agg(z.item order by z.created_at desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created_at, x."id" as id
    from "better_supabase"."assets" x
    where (list_assets.tenant is null or x."tenant_id" = list_assets.tenant)
      and (list_assets.location_id is null or x."location_id" in (select below.id from below))
      and (list_assets.kind is null or x."kind" = list_assets.kind)
      and (list_assets.status is null or x."status" = list_assets.status)
      and (list_assets.assignee_type is null or x."assignee_type" = list_assets.assignee_type)
      and (list_assets.assignee_id is null or x."assignee_id" = list_assets.assignee_id)
      and (list_assets.query is null or x."name" ilike '%' || list_assets.query || '%' or x."tag" = list_assets.query or x."serial_number" = list_assets.query)
      and (list_assets.before is null or x."created_at" < list_assets.before)
      and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)) or (x."assignee_type" = 'member' and x."assignee_id" = auth.uid()::text))
    order by x."created_at" desc, x."id"
    limit least(greatest(coalesce(list_assets.page_size, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."list_assets"(uuid, uuid, boolean, text, text, text, text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_assets"(uuid, uuid, boolean, text, text, text, text, text, timestamptz, integer) to authenticated, service_role;

-- An asset's assignments, newest first.
create or replace function "better_supabase"."asset_assignment_history"(asset_id uuid, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  select * into v_row from "better_supabase"."assets" x where x."id" = asset_assignment_history.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return coalesce((
    select jsonb_agg(z.item order by z.assigned_at desc, z.id)
    from (
      select jsonb_build_object('id', y."id", 'assetId', y."asset_id", 'assigneeType', y."assignee_type", 'assigneeId', y."assignee_id", 'note', y."note", 'assignedBy', y."assigned_by", 'assignedAt', y."assigned_at", 'releasedAt', y."released_at") as item, y."assigned_at" as assigned_at, y."id" as id
      from "better_supabase"."asset_assignments" y where y."asset_id" = v_row."id"
      order by y."assigned_at" desc, y."id"
      limit least(greatest(coalesce(asset_assignment_history.page_size, 50), 1), 500)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."asset_assignment_history"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."asset_assignment_history"(uuid, integer) to authenticated, service_role;

-- The assets and locations within radius_meters of a point, nearest first,
-- each with distanceMeters. The haversine distance on latitude and longitude.
create or replace function "better_supabase"."assets_near"(tenant uuid, latitude double precision, longitude double precision, radius_meters double precision, kind text default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dlat double precision := assets_near.radius_meters / 111320.0;
  v_dlng double precision := assets_near.radius_meters / (111320.0 * greatest(cos(radians(assets_near.latitude)), 0.01));
  v_limit integer := least(greatest(coalesce(assets_near.page_size, 50), 1), 500);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assets_near.tenant, 'assets.read'), false)) then
    raise exception 'not allowed to read assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if assets_near.latitude is null or assets_near.longitude is null or assets_near.latitude not between -90 and 90 or assets_near.longitude not between -180 and 180 then
    raise exception 'latitude must be between -90 and 90 and longitude between -180 and 180' using errcode = '22023', hint = 'ASSETS_POINT_INVALID';
  end if;
  if assets_near.radius_meters is null or assets_near.radius_meters <= 0 or assets_near.radius_meters > 1000000 then
    raise exception 'radius_meters must be above 0 and at most 1000000' using errcode = '22023', hint = 'ASSETS_RADIUS_INVALID';
  end if;
  return jsonb_build_object(
    'assets', coalesce((
      select jsonb_agg(z.item || jsonb_build_object('distanceMeters', z.distance) order by z.distance, z.id)
      from (
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
        from "better_supabase"."assets" x
        where x."tenant_id" = assets_near.tenant and x."latitude" is not null and x."status" <> 'retired'
          and (assets_near.kind is null or x."kind" = assets_near.kind)
          and x."latitude" between assets_near.latitude - v_dlat and assets_near.latitude + v_dlat
        and x."longitude" between assets_near.longitude - v_dlng and assets_near.longitude + v_dlng
        and (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) <= assets_near.radius_meters
        order by 2, 3
        limit v_limit
      ) z
    ), '[]'::jsonb),
    'locations', coalesce((
      select jsonb_agg(z.item || jsonb_build_object('distanceMeters', z.distance) order by z.distance, z.id)
      from (
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'parentId', x."parent_id", 'kind', x."kind", 'name', x."name", 'code', x."code", 'address', x."address", 'latitude', x."latitude", 'longitude', x."longitude", 'area', null::jsonb, 'metadata', x."metadata", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
        from "better_supabase"."asset_locations" x
        where x."tenant_id" = assets_near.tenant and x."latitude" is not null and x."archived_at" is null
          and x."latitude" between assets_near.latitude - v_dlat and assets_near.latitude + v_dlat
        and x."longitude" between assets_near.longitude - v_dlng and assets_near.longitude + v_dlng
        and (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) <= assets_near.radius_meters
        order by 2, 3
        limit v_limit
      ) z
    ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."assets_near"(uuid, double precision, double precision, double precision, text, integer) from public, anon;
grant execute on function "better_supabase"."assets_near"(uuid, double precision, double precision, double precision, text, integer) to authenticated, service_role;

-- The locations whose area contains a point, smallest area first. Needs the
-- postgis option.
create or replace function "better_supabase"."asset_locations_at"(tenant uuid, latitude double precision, longitude double precision)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', asset_locations_at.tenant, 'assets.read'), false)) then
    raise exception 'not allowed to read assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
end;
$$;
revoke execute on function "better_supabase"."asset_locations_at"(uuid, double precision, double precision) from public, anon;
grant execute on function "better_supabase"."asset_locations_at"(uuid, double precision, double precision) to authenticated, service_role;

-- Names the asset a booking resource or a work item is about; a null
-- asset_id clears it. target_type is booking_resource or work_item.
create or replace function "better_supabase"."set_asset_link"(target_type text, target_id uuid, asset_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  raise exception 'install bookings or work-items to link assets' using errcode = '22023', hint = 'ASSETS_LINK_UNSUPPORTED';
end;
$$;
revoke execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) to authenticated, service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_113_assets.sql
-- better-supabase module: assets
-- @bs-module-data assets
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_113_assets.sql
-- better-supabase module: assets
-- @bs-module assets@1 managed
-- A location hierarchy (site, building, unit) and an asset registry with tags, status, coordinates and assignment to members or records. Optional PostGIS stores points and areas as geography; bookings resources and work items can name an asset.
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
create table if not exists "better_supabase"."asset_locations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid references "better_supabase"."asset_locations" ("id") on delete restrict,
  -- site, building, floor, unit, room, or the app's own kind.
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "code" text check ("code" is null or length("code") between 1 and 100),
  "address" jsonb not null default '{}'::jsonb check (jsonb_typeof("address") = 'object'),
  "latitude" double precision check ("latitude" between -90 and 90),
  "longitude" double precision check ("longitude" between -180 and 180),
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  check (("latitude" is null) = ("longitude" is null))
);
create index if not exists "asset_locations_parent_idx" on "better_supabase"."asset_locations" ("tenant_id", "parent_id");
create index if not exists "asset_locations_coordinates_idx" on "better_supabase"."asset_locations" ("tenant_id", "latitude", "longitude") where "latitude" is not null;

create table if not exists "better_supabase"."assets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid references "better_supabase"."asset_locations" ("id") on delete set null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  -- The asset tag, unique per organization.
  "tag" text check ("tag" is null or length("tag") between 1 and 100),
  "serial_number" text check ("serial_number" is null or length("serial_number") <= 200),
  "status" text not null default 'active' check ("status" in ('active', 'maintenance', 'retired')),
  -- member (a user id) or a subject type such as party, with its id.
  "assignee_type" text check ("assignee_type" is null or "assignee_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "assignee_id" text,
  -- Where a moving asset (a vehicle) was last seen.
  "latitude" double precision check ("latitude" between -90 and 90),
  "longitude" double precision check ("longitude" between -180 and 180),
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "retired_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "tag"),
  check (("assignee_type" is null) = ("assignee_id" is null)),
  check (("latitude" is null) = ("longitude" is null))
);
create index if not exists "assets_location_idx" on "better_supabase"."assets" ("tenant_id", "location_id");
create index if not exists "assets_assignee_idx" on "better_supabase"."assets" ("tenant_id", "assignee_type", "assignee_id") where "assignee_type" is not null;
create index if not exists "assets_kind_idx" on "better_supabase"."assets" ("tenant_id", "kind", "status");
create index if not exists "assets_coordinates_idx" on "better_supabase"."assets" ("tenant_id", "latitude", "longitude") where "latitude" is not null;

create table if not exists "better_supabase"."asset_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "asset_id" uuid not null references "better_supabase"."assets" ("id") on delete cascade,
  "assignee_type" text not null,
  "assignee_id" text not null,
  "note" text check ("note" is null or length("note") <= 2000),
  "assigned_by" uuid,
  "assigned_at" timestamptz not null default now(),
  "released_at" timestamptz
);
create unique index if not exists "asset_assignments_open_idx" on "better_supabase"."asset_assignments" ("asset_id") where "released_at" is null;
create index if not exists "asset_assignments_history_idx" on "better_supabase"."asset_assignments" ("asset_id", "assigned_at" desc);

alter table "better_supabase"."asset_locations" enable row level security;
revoke all on "better_supabase"."asset_locations" from anon, authenticated;
grant select on "better_supabase"."asset_locations" to authenticated;
grant all on "better_supabase"."asset_locations" to service_role;
drop policy if exists "asset_locations_read" on "better_supabase"."asset_locations";
create policy "asset_locations_read" on "better_supabase"."asset_locations" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));
alter table "better_supabase"."assets" enable row level security;
revoke all on "better_supabase"."assets" from anon, authenticated;
grant select on "better_supabase"."assets" to authenticated;
grant all on "better_supabase"."assets" to service_role;
drop policy if exists "assets_read" on "better_supabase"."assets";
create policy "assets_read" on "better_supabase"."assets" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text));
alter table "better_supabase"."asset_assignments" enable row level security;
revoke all on "better_supabase"."asset_assignments" from anon, authenticated;
grant select on "better_supabase"."asset_assignments" to authenticated;
grant all on "better_supabase"."asset_assignments" to service_role;
drop policy if exists "asset_assignments_read" on "better_supabase"."asset_assignments";
create policy "asset_assignments_read" on "better_supabase"."asset_assignments" for select to authenticated
  using ("asset_id" in (select y."id" from "better_supabase"."assets" y));

-- A location's parent is in the same organization and never one of its own
-- descendants, so the hierarchy stays a tree.
create or replace function "better_supabase"."asset_location_check_parent"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."parent_id" is null then
    return new;
  end if;
  if not exists (
    select 1 from "better_supabase"."asset_locations" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id"
  ) then
    raise exception 'the parent location doesn''t exist in this organization' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if tg_op = 'UPDATE' and exists (
    with recursive up as (
      select x."id" as id, x."parent_id" as parent, 1 as depth from "better_supabase"."asset_locations" x where x."id" = new."parent_id"
      union all
      select x."id", x."parent_id", up.depth + 1 from "better_supabase"."asset_locations" x join up on x."id" = up.parent where up.depth < 64
    )
    select 1 from up where up.id = new."id"
  ) then
    raise exception 'a location can''t be inside one of its own sublocations' using errcode = '23514', hint = 'ASSETS_LOCATION_CYCLE';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."asset_location_check_parent"() from public, anon, authenticated;
drop trigger if exists "bs_asset_locations_parent" on "better_supabase"."asset_locations";
create trigger "bs_asset_locations_parent" before insert or update of "parent_id" on "better_supabase"."asset_locations"
  for each row execute function "better_supabase"."asset_location_check_parent"();
alter table "better_supabase"."booking_resources" add column if not exists asset_id uuid references "better_supabase"."assets" ("id") on delete set null;
create index if not exists "booking_resources_asset_idx" on "better_supabase"."booking_resources" (asset_id) where asset_id is not null;
alter table "better_supabase"."work_items" add column if not exists asset_id uuid references "better_supabase"."assets" ("id") on delete set null;
create index if not exists "work_items_asset_idx" on "better_supabase"."work_items" (asset_id) where asset_id is not null;

-- Adds a location (a site, building, floor, unit or room) under parent_id,
-- or at the top when it is null. area is GeoJSON and needs the postgis option.
create or replace function "better_supabase"."create_asset_location"(tenant uuid, kind text, name text, parent_id uuid default null, code text default null, address jsonb default null, latitude double precision default null, longitude double precision default null, area jsonb default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_asset_location.tenant, 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if create_asset_location.area is not null then
    raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
  end if;
  if create_asset_location.code is not null and exists (
    select 1 from "better_supabase"."asset_locations" x where x."tenant_id" = create_asset_location.tenant and x."code" = create_asset_location.code
  ) then
    raise exception 'a location with this code already exists' using errcode = '23505', hint = 'ASSETS_CODE_TAKEN';
  end if;
  insert into "better_supabase"."asset_locations" ("tenant_id", "parent_id", "kind", "name", "code", "address", "latitude", "longitude", "metadata")
  values (create_asset_location.tenant, create_asset_location.parent_id, create_asset_location.kind, trim(create_asset_location.name),
    create_asset_location.code, coalesce(create_asset_location.address, '{}'::jsonb), create_asset_location.latitude,
    create_asset_location.longitude, coalesce(create_asset_location.metadata, '{}'::jsonb))
  returning * into v_row;
  perform "better_supabase".emit_event('asset_location.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'parentId', v_row."parent_id"), 'asset-locations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset_location.created',
    category => 'data',
    target_type => 'asset_location',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created location',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'parentId', v_row."parent_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_asset_location"(uuid, text, text, uuid, text, jsonb, double precision, double precision, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_asset_location"(uuid, text, text, uuid, text, jsonb, double precision, double precision, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, parentId, code, address,
-- latitude, longitude, area and metadata. A null value clears an optional key.
create or replace function "better_supabase"."update_asset_location"(location_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."asset_locations" x where x."id" = update_asset_location.location_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_asset_location.patch) is distinct from 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'ASSETS_PATCH_INVALID';
  end if;
  if update_asset_location.patch ? 'area' and jsonb_typeof(update_asset_location.patch -> 'area') <> 'null' then
    raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
  end if;
  if update_asset_location.patch ? 'code' and update_asset_location.patch ->> 'code' is not null and exists (
    select 1 from "better_supabase"."asset_locations" x where x."tenant_id" = v_row."tenant_id" and x."code" = update_asset_location.patch ->> 'code' and x."id" <> v_row."id"
  ) then
    raise exception 'a location with this code already exists' using errcode = '23505', hint = 'ASSETS_CODE_TAKEN';
  end if;
  update "better_supabase"."asset_locations" x set
    "kind" = case when update_asset_location.patch ? 'kind' then update_asset_location.patch ->> 'kind' else x."kind" end,
    "name" = case when update_asset_location.patch ? 'name' then trim(update_asset_location.patch ->> 'name') else x."name" end,
    "parent_id" = case when update_asset_location.patch ? 'parentId' then (update_asset_location.patch ->> 'parentId')::uuid else x."parent_id" end,
    "code" = case when update_asset_location.patch ? 'code' then update_asset_location.patch ->> 'code' else x."code" end,
    "address" = case when update_asset_location.patch ? 'address' then coalesce(nullif(update_asset_location.patch -> 'address', 'null'::jsonb), '{}'::jsonb) else x."address" end,
    "latitude" = case when update_asset_location.patch ? 'latitude' then (update_asset_location.patch ->> 'latitude')::double precision else x."latitude" end,
    "longitude" = case when update_asset_location.patch ? 'longitude' then (update_asset_location.patch ->> 'longitude')::double precision else x."longitude" end,
    "metadata" = case when update_asset_location.patch ? 'metadata' then coalesce(nullif(update_asset_location.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x."metadata" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('asset_location.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'parentId', v_row."parent_id"), 'asset-locations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset_location.updated',
    category => 'data',
    target_type => 'asset_location',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated location',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'parentId', v_row."parent_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_asset_location"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_asset_location"(uuid, jsonb) to authenticated, service_role;

-- Archives a location with no open sublocations and no assets in service.
create or replace function "better_supabase"."archive_asset_location"(location_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."asset_locations" x where x."id" = archive_asset_location.location_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."asset_locations" y where y."parent_id" = v_row."id" and y."archived_at" is null)
    or exists (select 1 from "better_supabase"."assets" y where y."location_id" = v_row."id" and y."status" <> 'retired') then
    raise exception 'move or archive the sublocations and assets of this location first' using errcode = '55000', hint = 'ASSETS_LOCATION_IN_USE';
  end if;
  if v_row."archived_at" is null then
    update "better_supabase"."asset_locations" x set "archived_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase".emit_event('asset_location.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'parentId', v_row."parent_id"), 'asset-locations/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset_location.archived',
    category => 'data',
    target_type => 'asset_location',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'archived location',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'parentId', v_row."parent_id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_asset_location"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_asset_location"(uuid) to authenticated, service_role;

-- A location with its path from the top (path ends with the location itself)
-- and how many sublocations and assets it holds.
create or replace function "better_supabase"."get_asset_location"(location_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  select * into v_row from "better_supabase"."asset_locations" x where x."id" = get_asset_location.location_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'path', coalesce((
    with recursive up as (
      select y."id" as id, y."parent_id" as parent, y."kind" as kind, y."name" as name, 0 as depth from "better_supabase"."asset_locations" y where y."id" = v_row."id"
      union all
      select y."id", y."parent_id", y."kind", y."name", up.depth + 1 from "better_supabase"."asset_locations" y join up on y."id" = up.parent where up.depth < 64
    )
    select jsonb_agg(jsonb_build_object('id', up.id, 'kind', up.kind, 'name', up.name) order by up.depth desc) from up
  ), '[]'::jsonb),
    'locations', (select count(*)::integer from "better_supabase"."asset_locations" y where y."parent_id" = v_row."id" and y."archived_at" is null),
    'assets', (select count(*)::integer from "better_supabase"."assets" y where y."location_id" = v_row."id" and y."status" <> 'retired'));
end;
$$;
revoke execute on function "better_supabase"."get_asset_location"(uuid) from public, anon;
grant execute on function "better_supabase"."get_asset_location"(uuid) to authenticated, service_role;

-- The locations directly under parent_id, or the top ones when it is null.
create or replace function "better_supabase"."list_asset_locations"(tenant uuid, parent_id uuid default null, include_archived boolean default false, page_size integer default 200)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.name, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'parentId', x."parent_id", 'kind', x."kind", 'name', x."name", 'code', x."code", 'address', x."address", 'latitude', x."latitude", 'longitude', x."longitude", 'area', null::jsonb, 'metadata', x."metadata", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."name" as name, x."id" as id
    from "better_supabase"."asset_locations" x
    where x."tenant_id" = list_asset_locations.tenant
      and x."parent_id" is not distinct from list_asset_locations.parent_id
      and (coalesce(list_asset_locations.include_archived, false) or x."archived_at" is null)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false))
    order by x."name", x."id"
    limit least(greatest(coalesce(list_asset_locations.page_size, 200), 1), 1000)
  ) z
$$;
revoke execute on function "better_supabase"."list_asset_locations"(uuid, uuid, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_asset_locations"(uuid, uuid, boolean, integer) to authenticated, service_role;

-- Registers an asset, at location_id when given.
create or replace function "better_supabase"."create_asset"(tenant uuid, kind text, name text, location_id uuid default null, tag text default null, serial_number text default null, latitude double precision default null, longitude double precision default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_asset.tenant, 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if create_asset.location_id is not null and not exists (
    select 1 from "better_supabase"."asset_locations" y where y."id" = create_asset.location_id and y."tenant_id" = create_asset.tenant and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if create_asset.tag is not null and exists (
    select 1 from "better_supabase"."assets" x where x."tenant_id" = create_asset.tenant and x."tag" = create_asset.tag
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  insert into "better_supabase"."assets" ("tenant_id", "location_id", "kind", "name", "tag", "serial_number", "latitude", "longitude", "metadata", "created_by")
  values (create_asset.tenant, create_asset.location_id, create_asset.kind, trim(create_asset.name), create_asset.tag,
    create_asset.serial_number, create_asset.latitude, create_asset.longitude, coalesce(create_asset.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('asset.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id"), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.created',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) from public, anon;
grant execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, locationId, tag, serialNumber,
-- status, latitude, longitude and metadata. Retiring an asset releases it.
create or replace function "better_supabase"."update_asset"(asset_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
  v_location uuid;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = update_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_asset.patch) is distinct from 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'ASSETS_PATCH_INVALID';
  end if;
  v_location := case when update_asset.patch ? 'locationId' then (update_asset.patch ->> 'locationId')::uuid else v_row."location_id" end;
  if v_location is distinct from v_row."location_id" then
    if v_location is not null and not exists (
    select 1 from "better_supabase"."asset_locations" y where y."id" = v_location and y."tenant_id" = v_row."tenant_id" and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  end if;
  v_status := case when update_asset.patch ? 'status' then update_asset.patch ->> 'status' else v_row."status" end;
  if update_asset.patch ? 'tag' and update_asset.patch ->> 'tag' is not null and exists (
    select 1 from "better_supabase"."assets" x where x."tenant_id" = v_row."tenant_id" and x."tag" = update_asset.patch ->> 'tag' and x."id" <> v_row."id"
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  if v_status = 'retired' and v_row."status" <> 'retired' then
    update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  end if;
  update "better_supabase"."assets" x set
    "kind" = case when update_asset.patch ? 'kind' then update_asset.patch ->> 'kind' else x."kind" end,
    "name" = case when update_asset.patch ? 'name' then trim(update_asset.patch ->> 'name') else x."name" end,
    "location_id" = v_location,
    "tag" = case when update_asset.patch ? 'tag' then update_asset.patch ->> 'tag' else x."tag" end,
    "serial_number" = case when update_asset.patch ? 'serialNumber' then update_asset.patch ->> 'serialNumber' else x."serial_number" end,
    "status" = v_status,
    "latitude" = case when update_asset.patch ? 'latitude' then (update_asset.patch ->> 'latitude')::double precision else x."latitude" end,
    "longitude" = case when update_asset.patch ? 'longitude' then (update_asset.patch ->> 'longitude')::double precision else x."longitude" end,
    "metadata" = case when update_asset.patch ? 'metadata' then coalesce(nullif(update_asset.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x."metadata" end,
    "assignee_type" = case when v_status = 'retired' then null else x."assignee_type" end,
    "assignee_id" = case when v_status = 'retired' then null else x."assignee_id" end,
    "retired_at" = case when v_status = 'retired' then coalesce(x."retired_at", now()) else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('asset.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id"), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.updated',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_asset"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_asset"(uuid, jsonb) to authenticated, service_role;

-- Assigns an asset to a member (assignee_type member, a user id) or to a
-- record such as a party. The previous assignment ends.
create or replace function "better_supabase"."assign_asset"(asset_id uuid, assignee_type text, assignee_id text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = assign_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."status" = 'retired' then
    raise exception 'a retired asset can''t be assigned' using errcode = '55000', hint = 'ASSETS_RETIRED';
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
    raise exception 'an assignee needs a lowercase type and an id' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  if assign_asset.assignee_type = 'member' and (
    assign_asset.assignee_id !~ '^[0-9a-fA-F-]{36}$'
    or not coalesce(better_supabase.can_user(assign_asset.assignee_id::uuid, 'tenant', v_row."tenant_id", 'assets.read'), false)
  ) then
    raise exception 'the member can''t see this organization''s assets' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_asset_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using v_row."id", assign_asset.assignee_type, assign_asset.assignee_id;
    end if;
  end;
  update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  insert into "better_supabase"."asset_assignments" ("tenant_id", "asset_id", "assignee_type", "assignee_id", "note", "assigned_by")
  values (v_row."tenant_id", v_row."id", assign_asset.assignee_type, assign_asset.assignee_id, nullif(trim(assign_asset.note), ''), auth.uid());
  update "better_supabase"."assets" x set "assignee_type" = assign_asset.assignee_type, "assignee_id" = assign_asset.assignee_id, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('asset.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id"), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.assigned',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'assigned asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_asset_assign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."assign_asset"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."assign_asset"(uuid, text, text, text) to authenticated, service_role;

-- Ends the asset's current assignment; a no-op when it has none.
create or replace function "better_supabase"."release_asset"(asset_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = release_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."assignee_type" is not null then
    update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
    update "better_supabase"."assets" x set "assignee_type" = null, "assignee_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    perform "better_supabase".emit_event('asset.released', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id"), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.released',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'released asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."release_asset"(uuid) from public, anon;
grant execute on function "better_supabase"."release_asset"(uuid) to authenticated, service_role;

-- An asset with its location's path and the booking resources and open work
-- items that name it.
create or replace function "better_supabase"."get_asset"(asset_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  select * into v_row from "better_supabase"."assets" x where x."id" = get_asset.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'locationPath', case when v_row."location_id" is null then '[]'::jsonb else coalesce((
    with recursive up as (
      select y."id" as id, y."parent_id" as parent, y."kind" as kind, y."name" as name, 0 as depth from "better_supabase"."asset_locations" y where y."id" = v_row."location_id"
      union all
      select y."id", y."parent_id", y."kind", y."name", up.depth + 1 from "better_supabase"."asset_locations" y join up on y."id" = up.parent where up.depth < 64
    )
    select jsonb_agg(jsonb_build_object('id', up.id, 'kind', up.kind, 'name', up.name) order by up.depth desc) from up
  ), '[]'::jsonb) end,
    'links', jsonb_build_object('bookingResources', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name") order by y."name") from "better_supabase"."booking_resources" y where y.asset_id = v_row."id"), '[]'::jsonb), 'workItems', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'title', z.title) order by z.created_at desc) from (select y."id" as id, y."title" as title, y."created_at" as created_at from "better_supabase"."work_items" y where y.asset_id = v_row."id" and y."closed_at" is null order by y."created_at" desc limit 50) z), '[]'::jsonb)));
end;
$$;
revoke execute on function "better_supabase"."get_asset"(uuid) from public, anon;
grant execute on function "better_supabase"."get_asset"(uuid) to authenticated, service_role;

-- Assets newest first. With location_id, include_sublocations also returns
-- the assets below it. With tenant null an assignee decides the organization.
create or replace function "better_supabase"."list_assets"(tenant uuid, location_id uuid default null, include_sublocations boolean default false, kind text default null, status text default null, assignee_type text default null, assignee_id text default null, query text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with recursive below as (
    select y."id" as id, 0 as depth from "better_supabase"."asset_locations" y where y."id" = list_assets.location_id
    union all
    select y."id", below.depth + 1 from "better_supabase"."asset_locations" y join below on y."parent_id" = below.id
    where coalesce(list_assets.include_sublocations, false) and below.depth < 64
  )
  select coalesce(jsonb_agg(z.item order by z.created_at desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created_at, x."id" as id
    from "better_supabase"."assets" x
    where (list_assets.tenant is null or x."tenant_id" = list_assets.tenant)
      and (list_assets.location_id is null or x."location_id" in (select below.id from below))
      and (list_assets.kind is null or x."kind" = list_assets.kind)
      and (list_assets.status is null or x."status" = list_assets.status)
      and (list_assets.assignee_type is null or x."assignee_type" = list_assets.assignee_type)
      and (list_assets.assignee_id is null or x."assignee_id" = list_assets.assignee_id)
      and (list_assets.query is null or x."name" ilike '%' || list_assets.query || '%' or x."tag" = list_assets.query or x."serial_number" = list_assets.query)
      and (list_assets.before is null or x."created_at" < list_assets.before)
      and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)) or (x."assignee_type" = 'member' and x."assignee_id" = auth.uid()::text))
    order by x."created_at" desc, x."id"
    limit least(greatest(coalesce(list_assets.page_size, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."list_assets"(uuid, uuid, boolean, text, text, text, text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_assets"(uuid, uuid, boolean, text, text, text, text, text, timestamptz, integer) to authenticated, service_role;

-- An asset's assignments, newest first.
create or replace function "better_supabase"."asset_assignment_history"(asset_id uuid, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  select * into v_row from "better_supabase"."assets" x where x."id" = asset_assignment_history.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return coalesce((
    select jsonb_agg(z.item order by z.assigned_at desc, z.id)
    from (
      select jsonb_build_object('id', y."id", 'assetId', y."asset_id", 'assigneeType', y."assignee_type", 'assigneeId', y."assignee_id", 'note', y."note", 'assignedBy', y."assigned_by", 'assignedAt', y."assigned_at", 'releasedAt', y."released_at") as item, y."assigned_at" as assigned_at, y."id" as id
      from "better_supabase"."asset_assignments" y where y."asset_id" = v_row."id"
      order by y."assigned_at" desc, y."id"
      limit least(greatest(coalesce(asset_assignment_history.page_size, 50), 1), 500)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."asset_assignment_history"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."asset_assignment_history"(uuid, integer) to authenticated, service_role;

-- The assets and locations within radius_meters of a point, nearest first,
-- each with distanceMeters. The haversine distance on latitude and longitude.
create or replace function "better_supabase"."assets_near"(tenant uuid, latitude double precision, longitude double precision, radius_meters double precision, kind text default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dlat double precision := assets_near.radius_meters / 111320.0;
  v_dlng double precision := assets_near.radius_meters / (111320.0 * greatest(cos(radians(assets_near.latitude)), 0.01));
  v_limit integer := least(greatest(coalesce(assets_near.page_size, 50), 1), 500);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assets_near.tenant, 'assets.read'), false)) then
    raise exception 'not allowed to read assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if assets_near.latitude is null or assets_near.longitude is null or assets_near.latitude not between -90 and 90 or assets_near.longitude not between -180 and 180 then
    raise exception 'latitude must be between -90 and 90 and longitude between -180 and 180' using errcode = '22023', hint = 'ASSETS_POINT_INVALID';
  end if;
  if assets_near.radius_meters is null or assets_near.radius_meters <= 0 or assets_near.radius_meters > 1000000 then
    raise exception 'radius_meters must be above 0 and at most 1000000' using errcode = '22023', hint = 'ASSETS_RADIUS_INVALID';
  end if;
  return jsonb_build_object(
    'assets', coalesce((
      select jsonb_agg(z.item || jsonb_build_object('distanceMeters', z.distance) order by z.distance, z.id)
      from (
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
        from "better_supabase"."assets" x
        where x."tenant_id" = assets_near.tenant and x."latitude" is not null and x."status" <> 'retired'
          and (assets_near.kind is null or x."kind" = assets_near.kind)
          and x."latitude" between assets_near.latitude - v_dlat and assets_near.latitude + v_dlat
        and x."longitude" between assets_near.longitude - v_dlng and assets_near.longitude + v_dlng
        and (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) <= assets_near.radius_meters
        order by 2, 3
        limit v_limit
      ) z
    ), '[]'::jsonb),
    'locations', coalesce((
      select jsonb_agg(z.item || jsonb_build_object('distanceMeters', z.distance) order by z.distance, z.id)
      from (
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'parentId', x."parent_id", 'kind', x."kind", 'name', x."name", 'code', x."code", 'address', x."address", 'latitude', x."latitude", 'longitude', x."longitude", 'area', null::jsonb, 'metadata', x."metadata", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
        from "better_supabase"."asset_locations" x
        where x."tenant_id" = assets_near.tenant and x."latitude" is not null and x."archived_at" is null
          and x."latitude" between assets_near.latitude - v_dlat and assets_near.latitude + v_dlat
        and x."longitude" between assets_near.longitude - v_dlng and assets_near.longitude + v_dlng
        and (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) <= assets_near.radius_meters
        order by 2, 3
        limit v_limit
      ) z
    ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."assets_near"(uuid, double precision, double precision, double precision, text, integer) from public, anon;
grant execute on function "better_supabase"."assets_near"(uuid, double precision, double precision, double precision, text, integer) to authenticated, service_role;

-- The locations whose area contains a point, smallest area first. Needs the
-- postgis option.
create or replace function "better_supabase"."asset_locations_at"(tenant uuid, latitude double precision, longitude double precision)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', asset_locations_at.tenant, 'assets.read'), false)) then
    raise exception 'not allowed to read assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
end;
$$;
revoke execute on function "better_supabase"."asset_locations_at"(uuid, double precision, double precision) from public, anon;
grant execute on function "better_supabase"."asset_locations_at"(uuid, double precision, double precision) to authenticated, service_role;

-- Names the asset a booking resource or a work item is about; a null
-- asset_id clears it. target_type is booking_resource or work_item.
create or replace function "better_supabase"."set_asset_link"(target_type text, target_id uuid, asset_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  case set_asset_link.target_type
  when 'booking_resource' then
    select y."tenant_id" into v_tenant from "better_supabase"."booking_resources" y where y."id" = set_asset_link.target_id;
  when 'work_item' then
    select y."tenant_id" into v_tenant from "better_supabase"."work_items" y where y."id" = set_asset_link.target_id;
  else
    raise exception 'target_type must be booking_resource or work_item' using errcode = '22023', hint = 'ASSETS_LINK_UNSUPPORTED';
  end case;
  if v_tenant is null then
    raise exception 'the record to link doesn''t exist' using errcode = 'P0002', hint = 'ASSETS_LINK_TARGET_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if set_asset_link.asset_id is not null and not exists (
    select 1 from "better_supabase"."assets" y where y."id" = set_asset_link.asset_id and y."tenant_id" = v_tenant
  ) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if set_asset_link.target_type = 'booking_resource' then
    update "better_supabase"."booking_resources" y set asset_id = set_asset_link.asset_id where y."id" = set_asset_link.target_id;
  end if;
  if set_asset_link.target_type = 'work_item' then
    update "better_supabase"."work_items" y set asset_id = set_asset_link.asset_id where y."id" = set_asset_link.target_id;
  end if;
  return jsonb_build_object('targetType', set_asset_link.target_type, 'targetId', set_asset_link.target_id, 'assetId', set_asset_link.asset_id);
end;
$$;
revoke execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) to authenticated, service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_113_assets.sql
-- better-supabase module: assets
-- @bs-module-data assets
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_113_assets.sql
-- better-supabase module: assets
-- @bs-module assets@1 managed
-- A location hierarchy (site, building, unit) and an asset registry with tags, status, coordinates and assignment to members or records. Optional PostGIS stores points and areas as geography; bookings resources and work items can name an asset.
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
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
create table if not exists "app_private"."asset_locations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid references "app_private"."asset_locations" ("id") on delete restrict,
  -- site, building, floor, unit, room, or the app's own kind.
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "code" text check ("code" is null or length("code") between 1 and 100),
  "address" jsonb not null default '{}'::jsonb check (jsonb_typeof("address") = 'object'),
  "latitude" double precision check ("latitude" between -90 and 90),
  "longitude" double precision check ("longitude" between -180 and 180),
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  check (("latitude" is null) = ("longitude" is null))
);
create index if not exists "asset_locations_parent_idx" on "app_private"."asset_locations" ("tenant_id", "parent_id");
create index if not exists "asset_locations_coordinates_idx" on "app_private"."asset_locations" ("tenant_id", "latitude", "longitude") where "latitude" is not null;

create table if not exists "app_private"."assets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid references "app_private"."asset_locations" ("id") on delete set null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  -- The asset tag, unique per organization.
  "tag" text check ("tag" is null or length("tag") between 1 and 100),
  "serial_number" text check ("serial_number" is null or length("serial_number") <= 200),
  "status" text not null default 'active' check ("status" in ('active', 'maintenance', 'retired')),
  -- member (a user id) or a subject type such as party, with its id.
  "assignee_type" text check ("assignee_type" is null or "assignee_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "assignee_id" text,
  -- Where a moving asset (a vehicle) was last seen.
  "latitude" double precision check ("latitude" between -90 and 90),
  "longitude" double precision check ("longitude" between -180 and 180),
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "retired_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "tag"),
  check (("assignee_type" is null) = ("assignee_id" is null)),
  check (("latitude" is null) = ("longitude" is null))
);
create index if not exists "assets_location_idx" on "app_private"."assets" ("tenant_id", "location_id");
create index if not exists "assets_assignee_idx" on "app_private"."assets" ("tenant_id", "assignee_type", "assignee_id") where "assignee_type" is not null;
create index if not exists "assets_kind_idx" on "app_private"."assets" ("tenant_id", "kind", "status");
create index if not exists "assets_coordinates_idx" on "app_private"."assets" ("tenant_id", "latitude", "longitude") where "latitude" is not null;

create table if not exists "app_private"."asset_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "asset_id" uuid not null references "app_private"."assets" ("id") on delete cascade,
  "assignee_type" text not null,
  "assignee_id" text not null,
  "note" text check ("note" is null or length("note") <= 2000),
  "assigned_by" uuid,
  "assigned_at" timestamptz not null default now(),
  "released_at" timestamptz
);
create unique index if not exists "asset_assignments_open_idx" on "app_private"."asset_assignments" ("asset_id") where "released_at" is null;
create index if not exists "asset_assignments_history_idx" on "app_private"."asset_assignments" ("asset_id", "assigned_at" desc);

alter table "app_private"."asset_locations" enable row level security;
revoke all on "app_private"."asset_locations" from anon, authenticated;
grant select on "app_private"."asset_locations" to authenticated;
grant all on "app_private"."asset_locations" to service_role;
drop policy if exists "asset_locations_read" on "app_private"."asset_locations";
create policy "asset_locations_read" on "app_private"."asset_locations" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));
alter table "app_private"."assets" enable row level security;
revoke all on "app_private"."assets" from anon, authenticated;
grant select on "app_private"."assets" to authenticated;
grant all on "app_private"."assets" to service_role;
drop policy if exists "assets_read" on "app_private"."assets";
create policy "assets_read" on "app_private"."assets" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text));
alter table "app_private"."asset_assignments" enable row level security;
revoke all on "app_private"."asset_assignments" from anon, authenticated;
grant select on "app_private"."asset_assignments" to authenticated;
grant all on "app_private"."asset_assignments" to service_role;
drop policy if exists "asset_assignments_read" on "app_private"."asset_assignments";
create policy "asset_assignments_read" on "app_private"."asset_assignments" for select to authenticated
  using ("asset_id" in (select y."id" from "app_private"."assets" y));

-- A location's parent is in the same organization and never one of its own
-- descendants, so the hierarchy stays a tree.
create or replace function "app_private"."asset_location_check_parent"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."parent_id" is null then
    return new;
  end if;
  if not exists (
    select 1 from "app_private"."asset_locations" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id"
  ) then
    raise exception 'the parent location doesn''t exist in this organization' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if tg_op = 'UPDATE' and exists (
    with recursive up as (
      select x."id" as id, x."parent_id" as parent, 1 as depth from "app_private"."asset_locations" x where x."id" = new."parent_id"
      union all
      select x."id", x."parent_id", up.depth + 1 from "app_private"."asset_locations" x join up on x."id" = up.parent where up.depth < 64
    )
    select 1 from up where up.id = new."id"
  ) then
    raise exception 'a location can''t be inside one of its own sublocations' using errcode = '23514', hint = 'ASSETS_LOCATION_CYCLE';
  end if;
  return new;
end;
$$;
revoke execute on function "app_private"."asset_location_check_parent"() from public, anon, authenticated;
drop trigger if exists "bs_asset_locations_parent" on "app_private"."asset_locations";
create trigger "bs_asset_locations_parent" before insert or update of "parent_id" on "app_private"."asset_locations"
  for each row execute function "app_private"."asset_location_check_parent"();


-- Adds a location (a site, building, floor, unit or room) under parent_id,
-- or at the top when it is null. area is GeoJSON and needs the postgis option.
create or replace function "app_private"."create_asset_location"(tenant uuid, kind text, name text, parent_id uuid default null, code text default null, address jsonb default null, latitude double precision default null, longitude double precision default null, area jsonb default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_asset_location.tenant, 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if create_asset_location.area is not null then
    raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
  end if;
  if create_asset_location.code is not null and exists (
    select 1 from "app_private"."asset_locations" x where x."tenant_id" = create_asset_location.tenant and x."code" = create_asset_location.code
  ) then
    raise exception 'a location with this code already exists' using errcode = '23505', hint = 'ASSETS_CODE_TAKEN';
  end if;
  insert into "app_private"."asset_locations" ("tenant_id", "parent_id", "kind", "name", "code", "address", "latitude", "longitude", "metadata")
  values (create_asset_location.tenant, create_asset_location.parent_id, create_asset_location.kind, trim(create_asset_location.name),
    create_asset_location.code, coalesce(create_asset_location.address, '{}'::jsonb), create_asset_location.latitude,
    create_asset_location.longitude, coalesce(create_asset_location.metadata, '{}'::jsonb))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."create_asset_location"(uuid, text, text, uuid, text, jsonb, double precision, double precision, jsonb, jsonb) from public, anon;
grant execute on function "app_private"."create_asset_location"(uuid, text, text, uuid, text, jsonb, double precision, double precision, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, parentId, code, address,
-- latitude, longitude, area and metadata. A null value clears an optional key.
create or replace function "app_private"."update_asset_location"(location_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."asset_locations" x where x."id" = update_asset_location.location_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_asset_location.patch) is distinct from 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'ASSETS_PATCH_INVALID';
  end if;
  if update_asset_location.patch ? 'area' and jsonb_typeof(update_asset_location.patch -> 'area') <> 'null' then
    raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
  end if;
  if update_asset_location.patch ? 'code' and update_asset_location.patch ->> 'code' is not null and exists (
    select 1 from "app_private"."asset_locations" x where x."tenant_id" = v_row."tenant_id" and x."code" = update_asset_location.patch ->> 'code' and x."id" <> v_row."id"
  ) then
    raise exception 'a location with this code already exists' using errcode = '23505', hint = 'ASSETS_CODE_TAKEN';
  end if;
  update "app_private"."asset_locations" x set
    "kind" = case when update_asset_location.patch ? 'kind' then update_asset_location.patch ->> 'kind' else x."kind" end,
    "name" = case when update_asset_location.patch ? 'name' then trim(update_asset_location.patch ->> 'name') else x."name" end,
    "parent_id" = case when update_asset_location.patch ? 'parentId' then (update_asset_location.patch ->> 'parentId')::uuid else x."parent_id" end,
    "code" = case when update_asset_location.patch ? 'code' then update_asset_location.patch ->> 'code' else x."code" end,
    "address" = case when update_asset_location.patch ? 'address' then coalesce(nullif(update_asset_location.patch -> 'address', 'null'::jsonb), '{}'::jsonb) else x."address" end,
    "latitude" = case when update_asset_location.patch ? 'latitude' then (update_asset_location.patch ->> 'latitude')::double precision else x."latitude" end,
    "longitude" = case when update_asset_location.patch ? 'longitude' then (update_asset_location.patch ->> 'longitude')::double precision else x."longitude" end,
    "metadata" = case when update_asset_location.patch ? 'metadata' then coalesce(nullif(update_asset_location.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x."metadata" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."update_asset_location"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_asset_location"(uuid, jsonb) to authenticated, service_role;

-- Archives a location with no open sublocations and no assets in service.
create or replace function "app_private"."archive_asset_location"(location_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."asset_locations" x where x."id" = archive_asset_location.location_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if exists (select 1 from "app_private"."asset_locations" y where y."parent_id" = v_row."id" and y."archived_at" is null)
    or exists (select 1 from "app_private"."assets" y where y."location_id" = v_row."id" and y."status" <> 'retired') then
    raise exception 'move or archive the sublocations and assets of this location first' using errcode = '55000', hint = 'ASSETS_LOCATION_IN_USE';
  end if;
  if v_row."archived_at" is null then
    update "app_private"."asset_locations" x set "archived_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."archive_asset_location"(uuid) from public, anon;
grant execute on function "app_private"."archive_asset_location"(uuid) to authenticated, service_role;

-- A location with its path from the top (path ends with the location itself)
-- and how many sublocations and assets it holds.
create or replace function "app_private"."get_asset_location"(location_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."asset_locations"%rowtype;
begin
  select * into v_row from "app_private"."asset_locations" x where x."id" = get_asset_location.location_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'path', coalesce((
    with recursive up as (
      select y."id" as id, y."parent_id" as parent, y."kind" as kind, y."name" as name, 0 as depth from "app_private"."asset_locations" y where y."id" = v_row."id"
      union all
      select y."id", y."parent_id", y."kind", y."name", up.depth + 1 from "app_private"."asset_locations" y join up on y."id" = up.parent where up.depth < 64
    )
    select jsonb_agg(jsonb_build_object('id', up.id, 'kind', up.kind, 'name', up.name) order by up.depth desc) from up
  ), '[]'::jsonb),
    'locations', (select count(*)::integer from "app_private"."asset_locations" y where y."parent_id" = v_row."id" and y."archived_at" is null),
    'assets', (select count(*)::integer from "app_private"."assets" y where y."location_id" = v_row."id" and y."status" <> 'retired'));
end;
$$;
revoke execute on function "app_private"."get_asset_location"(uuid) from public, anon;
grant execute on function "app_private"."get_asset_location"(uuid) to authenticated, service_role;

-- The locations directly under parent_id, or the top ones when it is null.
create or replace function "app_private"."list_asset_locations"(tenant uuid, parent_id uuid default null, include_archived boolean default false, page_size integer default 200)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.name, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'parentId', x."parent_id", 'kind', x."kind", 'name', x."name", 'code', x."code", 'address', x."address", 'latitude', x."latitude", 'longitude', x."longitude", 'area', null::jsonb, 'metadata', x."metadata", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."name" as name, x."id" as id
    from "app_private"."asset_locations" x
    where x."tenant_id" = list_asset_locations.tenant
      and x."parent_id" is not distinct from list_asset_locations.parent_id
      and (coalesce(list_asset_locations.include_archived, false) or x."archived_at" is null)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false))
    order by x."name", x."id"
    limit least(greatest(coalesce(list_asset_locations.page_size, 200), 1), 1000)
  ) z
$$;
revoke execute on function "app_private"."list_asset_locations"(uuid, uuid, boolean, integer) from public, anon;
grant execute on function "app_private"."list_asset_locations"(uuid, uuid, boolean, integer) to authenticated, service_role;

-- Registers an asset, at location_id when given.
create or replace function "app_private"."create_asset"(tenant uuid, kind text, name text, location_id uuid default null, tag text default null, serial_number text default null, latitude double precision default null, longitude double precision default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_asset.tenant, 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if create_asset.location_id is not null and not exists (
    select 1 from "app_private"."asset_locations" y where y."id" = create_asset.location_id and y."tenant_id" = create_asset.tenant and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if create_asset.tag is not null and exists (
    select 1 from "app_private"."assets" x where x."tenant_id" = create_asset.tenant and x."tag" = create_asset.tag
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  insert into "app_private"."assets" ("tenant_id", "location_id", "kind", "name", "tag", "serial_number", "latitude", "longitude", "metadata", "created_by")
  values (create_asset.tenant, create_asset.location_id, create_asset.kind, trim(create_asset.name), create_asset.tag,
    create_asset.serial_number, create_asset.latitude, create_asset.longitude, coalesce(create_asset.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) from public, anon;
grant execute on function "app_private"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, locationId, tag, serialNumber,
-- status, latitude, longitude and metadata. Retiring an asset releases it.
create or replace function "app_private"."update_asset"(asset_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."assets"%rowtype;
  v_location uuid;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."assets" x where x."id" = update_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_asset.patch) is distinct from 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'ASSETS_PATCH_INVALID';
  end if;
  v_location := case when update_asset.patch ? 'locationId' then (update_asset.patch ->> 'locationId')::uuid else v_row."location_id" end;
  if v_location is distinct from v_row."location_id" then
    if v_location is not null and not exists (
    select 1 from "app_private"."asset_locations" y where y."id" = v_location and y."tenant_id" = v_row."tenant_id" and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  end if;
  v_status := case when update_asset.patch ? 'status' then update_asset.patch ->> 'status' else v_row."status" end;
  if update_asset.patch ? 'tag' and update_asset.patch ->> 'tag' is not null and exists (
    select 1 from "app_private"."assets" x where x."tenant_id" = v_row."tenant_id" and x."tag" = update_asset.patch ->> 'tag' and x."id" <> v_row."id"
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  if v_status = 'retired' and v_row."status" <> 'retired' then
    update "app_private"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  end if;
  update "app_private"."assets" x set
    "kind" = case when update_asset.patch ? 'kind' then update_asset.patch ->> 'kind' else x."kind" end,
    "name" = case when update_asset.patch ? 'name' then trim(update_asset.patch ->> 'name') else x."name" end,
    "location_id" = v_location,
    "tag" = case when update_asset.patch ? 'tag' then update_asset.patch ->> 'tag' else x."tag" end,
    "serial_number" = case when update_asset.patch ? 'serialNumber' then update_asset.patch ->> 'serialNumber' else x."serial_number" end,
    "status" = v_status,
    "latitude" = case when update_asset.patch ? 'latitude' then (update_asset.patch ->> 'latitude')::double precision else x."latitude" end,
    "longitude" = case when update_asset.patch ? 'longitude' then (update_asset.patch ->> 'longitude')::double precision else x."longitude" end,
    "metadata" = case when update_asset.patch ? 'metadata' then coalesce(nullif(update_asset.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x."metadata" end,
    "assignee_type" = case when v_status = 'retired' then null else x."assignee_type" end,
    "assignee_id" = case when v_status = 'retired' then null else x."assignee_id" end,
    "retired_at" = case when v_status = 'retired' then coalesce(x."retired_at", now()) else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."update_asset"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_asset"(uuid, jsonb) to authenticated, service_role;

-- Assigns an asset to a member (assignee_type member, a user id) or to a
-- record such as a party. The previous assignment ends.
create or replace function "app_private"."assign_asset"(asset_id uuid, assignee_type text, assignee_id text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."assets" x where x."id" = assign_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."status" = 'retired' then
    raise exception 'a retired asset can''t be assigned' using errcode = '55000', hint = 'ASSETS_RETIRED';
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
    raise exception 'an assignee needs a lowercase type and an id' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  if assign_asset.assignee_type = 'member' and (
    assign_asset.assignee_id !~ '^[0-9a-fA-F-]{36}$'
    or not coalesce(better_supabase.can_user(assign_asset.assignee_id::uuid, 'tenant', v_row."tenant_id", 'assets.read'), false)
  ) then
    raise exception 'the member can''t see this organization''s assets' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_asset_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using v_row."id", assign_asset.assignee_type, assign_asset.assignee_id;
    end if;
  end;
  update "app_private"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  insert into "app_private"."asset_assignments" ("tenant_id", "asset_id", "assignee_type", "assignee_id", "note", "assigned_by")
  values (v_row."tenant_id", v_row."id", assign_asset.assignee_type, assign_asset.assignee_id, nullif(trim(assign_asset.note), ''), auth.uid());
  update "app_private"."assets" x set "assignee_type" = assign_asset.assignee_type, "assignee_id" = assign_asset.assignee_id, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_asset_assign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."assign_asset"(uuid, text, text, text) from public, anon;
grant execute on function "app_private"."assign_asset"(uuid, text, text, text) to authenticated, service_role;

-- Ends the asset's current assignment; a no-op when it has none.
create or replace function "app_private"."release_asset"(asset_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."assets" x where x."id" = release_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."assignee_type" is not null then
    update "app_private"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
    update "app_private"."assets" x set "assignee_type" = null, "assignee_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."release_asset"(uuid) from public, anon;
grant execute on function "app_private"."release_asset"(uuid) to authenticated, service_role;

-- An asset with its location's path and the booking resources and open work
-- items that name it.
create or replace function "app_private"."get_asset"(asset_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."assets"%rowtype;
begin
  select * into v_row from "app_private"."assets" x where x."id" = get_asset.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'locationPath', case when v_row."location_id" is null then '[]'::jsonb else coalesce((
    with recursive up as (
      select y."id" as id, y."parent_id" as parent, y."kind" as kind, y."name" as name, 0 as depth from "app_private"."asset_locations" y where y."id" = v_row."location_id"
      union all
      select y."id", y."parent_id", y."kind", y."name", up.depth + 1 from "app_private"."asset_locations" y join up on y."id" = up.parent where up.depth < 64
    )
    select jsonb_agg(jsonb_build_object('id', up.id, 'kind', up.kind, 'name', up.name) order by up.depth desc) from up
  ), '[]'::jsonb) end,
    'links', jsonb_build_object('bookingResources', '[]'::jsonb, 'workItems', '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."get_asset"(uuid) from public, anon;
grant execute on function "app_private"."get_asset"(uuid) to authenticated, service_role;

-- Assets newest first. With location_id, include_sublocations also returns
-- the assets below it. With tenant null an assignee decides the organization.
create or replace function "app_private"."list_assets"(tenant uuid, location_id uuid default null, include_sublocations boolean default false, kind text default null, status text default null, assignee_type text default null, assignee_id text default null, query text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with recursive below as (
    select y."id" as id, 0 as depth from "app_private"."asset_locations" y where y."id" = list_assets.location_id
    union all
    select y."id", below.depth + 1 from "app_private"."asset_locations" y join below on y."parent_id" = below.id
    where coalesce(list_assets.include_sublocations, false) and below.depth < 64
  )
  select coalesce(jsonb_agg(z.item order by z.created_at desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created_at, x."id" as id
    from "app_private"."assets" x
    where (list_assets.tenant is null or x."tenant_id" = list_assets.tenant)
      and (list_assets.location_id is null or x."location_id" in (select below.id from below))
      and (list_assets.kind is null or x."kind" = list_assets.kind)
      and (list_assets.status is null or x."status" = list_assets.status)
      and (list_assets.assignee_type is null or x."assignee_type" = list_assets.assignee_type)
      and (list_assets.assignee_id is null or x."assignee_id" = list_assets.assignee_id)
      and (list_assets.query is null or x."name" ilike '%' || list_assets.query || '%' or x."tag" = list_assets.query or x."serial_number" = list_assets.query)
      and (list_assets.before is null or x."created_at" < list_assets.before)
      and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)) or (x."assignee_type" = 'member' and x."assignee_id" = auth.uid()::text))
    order by x."created_at" desc, x."id"
    limit least(greatest(coalesce(list_assets.page_size, 50), 1), 500)
  ) z
$$;
revoke execute on function "app_private"."list_assets"(uuid, uuid, boolean, text, text, text, text, text, timestamptz, integer) from public, anon;
grant execute on function "app_private"."list_assets"(uuid, uuid, boolean, text, text, text, text, text, timestamptz, integer) to authenticated, service_role;

-- An asset's assignments, newest first.
create or replace function "app_private"."asset_assignment_history"(asset_id uuid, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."assets"%rowtype;
begin
  select * into v_row from "app_private"."assets" x where x."id" = asset_assignment_history.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return coalesce((
    select jsonb_agg(z.item order by z.assigned_at desc, z.id)
    from (
      select jsonb_build_object('id', y."id", 'assetId', y."asset_id", 'assigneeType', y."assignee_type", 'assigneeId', y."assignee_id", 'note', y."note", 'assignedBy', y."assigned_by", 'assignedAt', y."assigned_at", 'releasedAt', y."released_at") as item, y."assigned_at" as assigned_at, y."id" as id
      from "app_private"."asset_assignments" y where y."asset_id" = v_row."id"
      order by y."assigned_at" desc, y."id"
      limit least(greatest(coalesce(asset_assignment_history.page_size, 50), 1), 500)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."asset_assignment_history"(uuid, integer) from public, anon;
grant execute on function "app_private"."asset_assignment_history"(uuid, integer) to authenticated, service_role;

-- The assets and locations within radius_meters of a point, nearest first,
-- each with distanceMeters. The haversine distance on latitude and longitude.
create or replace function "app_private"."assets_near"(tenant uuid, latitude double precision, longitude double precision, radius_meters double precision, kind text default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dlat double precision := assets_near.radius_meters / 111320.0;
  v_dlng double precision := assets_near.radius_meters / (111320.0 * greatest(cos(radians(assets_near.latitude)), 0.01));
  v_limit integer := least(greatest(coalesce(assets_near.page_size, 50), 1), 500);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assets_near.tenant, 'assets.read'), false)) then
    raise exception 'not allowed to read assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if assets_near.latitude is null or assets_near.longitude is null or assets_near.latitude not between -90 and 90 or assets_near.longitude not between -180 and 180 then
    raise exception 'latitude must be between -90 and 90 and longitude between -180 and 180' using errcode = '22023', hint = 'ASSETS_POINT_INVALID';
  end if;
  if assets_near.radius_meters is null or assets_near.radius_meters <= 0 or assets_near.radius_meters > 1000000 then
    raise exception 'radius_meters must be above 0 and at most 1000000' using errcode = '22023', hint = 'ASSETS_RADIUS_INVALID';
  end if;
  return jsonb_build_object(
    'assets', coalesce((
      select jsonb_agg(z.item || jsonb_build_object('distanceMeters', z.distance) order by z.distance, z.id)
      from (
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
        from "app_private"."assets" x
        where x."tenant_id" = assets_near.tenant and x."latitude" is not null and x."status" <> 'retired'
          and (assets_near.kind is null or x."kind" = assets_near.kind)
          and x."latitude" between assets_near.latitude - v_dlat and assets_near.latitude + v_dlat
        and x."longitude" between assets_near.longitude - v_dlng and assets_near.longitude + v_dlng
        and (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) <= assets_near.radius_meters
        order by 2, 3
        limit v_limit
      ) z
    ), '[]'::jsonb),
    'locations', coalesce((
      select jsonb_agg(z.item || jsonb_build_object('distanceMeters', z.distance) order by z.distance, z.id)
      from (
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'parentId', x."parent_id", 'kind', x."kind", 'name', x."name", 'code', x."code", 'address', x."address", 'latitude', x."latitude", 'longitude', x."longitude", 'area', null::jsonb, 'metadata', x."metadata", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
        from "app_private"."asset_locations" x
        where x."tenant_id" = assets_near.tenant and x."latitude" is not null and x."archived_at" is null
          and x."latitude" between assets_near.latitude - v_dlat and assets_near.latitude + v_dlat
        and x."longitude" between assets_near.longitude - v_dlng and assets_near.longitude + v_dlng
        and (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) <= assets_near.radius_meters
        order by 2, 3
        limit v_limit
      ) z
    ), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."assets_near"(uuid, double precision, double precision, double precision, text, integer) from public, anon;
grant execute on function "app_private"."assets_near"(uuid, double precision, double precision, double precision, text, integer) to authenticated, service_role;

-- The locations whose area contains a point, smallest area first. Needs the
-- postgis option.
create or replace function "app_private"."asset_locations_at"(tenant uuid, latitude double precision, longitude double precision)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', asset_locations_at.tenant, 'assets.read'), false)) then
    raise exception 'not allowed to read assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
end;
$$;
revoke execute on function "app_private"."asset_locations_at"(uuid, double precision, double precision) from public, anon;
grant execute on function "app_private"."asset_locations_at"(uuid, double precision, double precision) to authenticated, service_role;

-- Names the asset a booking resource or a work item is about; a null
-- asset_id clears it. target_type is booking_resource or work_item.
create or replace function "app_private"."set_asset_link"(target_type text, target_id uuid, asset_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  raise exception 'install bookings or work-items to link assets' using errcode = '22023', hint = 'ASSETS_LINK_UNSUPPORTED';
end;
$$;
revoke execute on function "app_private"."set_asset_link"(text, uuid, uuid) from public, anon;
grant execute on function "app_private"."set_asset_link"(text, uuid, uuid) to authenticated, service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_113_assets.sql
-- better-supabase module: assets
-- @bs-module-data assets
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_113_assets.sql
-- better-supabase module: assets
-- @bs-module assets@1 managed
-- A location hierarchy (site, building, unit) and an asset registry with tags, status, coordinates and assignment to members or records. Optional PostGIS stores points and areas as geography; bookings resources and work items can name an asset.
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
create table if not exists "better_supabase"."asset_locations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid references "better_supabase"."asset_locations" ("id") on delete restrict,
  -- site, building, floor, unit, room, or the app's own kind.
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "code" text check ("code" is null or length("code") between 1 and 100),
  "address" jsonb not null default '{}'::jsonb check (jsonb_typeof("address") = 'object'),
  "latitude" double precision check ("latitude" between -90 and 90),
  "longitude" double precision check ("longitude" between -180 and 180),
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code"),
  check (("latitude" is null) = ("longitude" is null))
);
create index if not exists "asset_locations_parent_idx" on "better_supabase"."asset_locations" ("tenant_id", "parent_id");
create index if not exists "asset_locations_coordinates_idx" on "better_supabase"."asset_locations" ("tenant_id", "latitude", "longitude") where "latitude" is not null;

create table if not exists "better_supabase"."assets" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "location_id" uuid references "better_supabase"."asset_locations" ("id") on delete set null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  -- The asset tag, unique per organization.
  "tag" text check ("tag" is null or length("tag") between 1 and 100),
  "serial_number" text check ("serial_number" is null or length("serial_number") <= 200),
  "status" text not null default 'active' check ("status" in ('active', 'maintenance', 'retired')),
  -- member (a user id) or a subject type such as party, with its id.
  "assignee_type" text check ("assignee_type" is null or "assignee_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "assignee_id" text,
  -- Where a moving asset (a vehicle) was last seen.
  "latitude" double precision check ("latitude" between -90 and 90),
  "longitude" double precision check ("longitude" between -180 and 180),
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "retired_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "tag"),
  check (("assignee_type" is null) = ("assignee_id" is null)),
  check (("latitude" is null) = ("longitude" is null))
);
create index if not exists "assets_location_idx" on "better_supabase"."assets" ("tenant_id", "location_id");
create index if not exists "assets_assignee_idx" on "better_supabase"."assets" ("tenant_id", "assignee_type", "assignee_id") where "assignee_type" is not null;
create index if not exists "assets_kind_idx" on "better_supabase"."assets" ("tenant_id", "kind", "status");
create index if not exists "assets_coordinates_idx" on "better_supabase"."assets" ("tenant_id", "latitude", "longitude") where "latitude" is not null;

create table if not exists "better_supabase"."asset_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "asset_id" uuid not null references "better_supabase"."assets" ("id") on delete cascade,
  "assignee_type" text not null,
  "assignee_id" text not null,
  "note" text check ("note" is null or length("note") <= 2000),
  "assigned_by" uuid,
  "assigned_at" timestamptz not null default now(),
  "released_at" timestamptz
);
create unique index if not exists "asset_assignments_open_idx" on "better_supabase"."asset_assignments" ("asset_id") where "released_at" is null;
create index if not exists "asset_assignments_history_idx" on "better_supabase"."asset_assignments" ("asset_id", "assigned_at" desc);

alter table "better_supabase"."asset_locations" enable row level security;
revoke all on "better_supabase"."asset_locations" from anon, authenticated;
grant select on "better_supabase"."asset_locations" to authenticated;
grant all on "better_supabase"."asset_locations" to service_role;
drop policy if exists "asset_locations_read" on "better_supabase"."asset_locations";
create policy "asset_locations_read" on "better_supabase"."asset_locations" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));
alter table "better_supabase"."assets" enable row level security;
revoke all on "better_supabase"."assets" from anon, authenticated;
grant select on "better_supabase"."assets" to authenticated;
grant all on "better_supabase"."assets" to service_role;
drop policy if exists "assets_read" on "better_supabase"."assets";
create policy "assets_read" on "better_supabase"."assets" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text));
alter table "better_supabase"."asset_assignments" enable row level security;
revoke all on "better_supabase"."asset_assignments" from anon, authenticated;
grant select on "better_supabase"."asset_assignments" to authenticated;
grant all on "better_supabase"."asset_assignments" to service_role;
drop policy if exists "asset_assignments_read" on "better_supabase"."asset_assignments";
create policy "asset_assignments_read" on "better_supabase"."asset_assignments" for select to authenticated
  using ("asset_id" in (select y."id" from "better_supabase"."assets" y));

-- A location's parent is in the same organization and never one of its own
-- descendants, so the hierarchy stays a tree.
create or replace function "better_supabase"."asset_location_check_parent"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."parent_id" is null then
    return new;
  end if;
  if not exists (
    select 1 from "better_supabase"."asset_locations" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id"
  ) then
    raise exception 'the parent location doesn''t exist in this organization' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if tg_op = 'UPDATE' and exists (
    with recursive up as (
      select x."id" as id, x."parent_id" as parent, 1 as depth from "better_supabase"."asset_locations" x where x."id" = new."parent_id"
      union all
      select x."id", x."parent_id", up.depth + 1 from "better_supabase"."asset_locations" x join up on x."id" = up.parent where up.depth < 64
    )
    select 1 from up where up.id = new."id"
  ) then
    raise exception 'a location can''t be inside one of its own sublocations' using errcode = '23514', hint = 'ASSETS_LOCATION_CYCLE';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."asset_location_check_parent"() from public, anon, authenticated;
drop trigger if exists "bs_asset_locations_parent" on "better_supabase"."asset_locations";
create trigger "bs_asset_locations_parent" before insert or update of "parent_id" on "better_supabase"."asset_locations"
  for each row execute function "better_supabase"."asset_location_check_parent"();


-- Adds a location (a site, building, floor, unit or room) under parent_id,
-- or at the top when it is null. area is GeoJSON and needs the postgis option.
create or replace function "better_supabase"."create_asset_location"(tenant uuid, kind text, name text, parent_id uuid default null, code text default null, address jsonb default null, latitude double precision default null, longitude double precision default null, area jsonb default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_asset_location.tenant, 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if create_asset_location.area is not null then
    raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
  end if;
  if create_asset_location.code is not null and exists (
    select 1 from "better_supabase"."asset_locations" x where x."tenant_id" = create_asset_location.tenant and x."code" = create_asset_location.code
  ) then
    raise exception 'a location with this code already exists' using errcode = '23505', hint = 'ASSETS_CODE_TAKEN';
  end if;
  insert into "better_supabase"."asset_locations" ("tenant_id", "parent_id", "kind", "name", "code", "address", "latitude", "longitude", "metadata")
  values (create_asset_location.tenant, create_asset_location.parent_id, create_asset_location.kind, trim(create_asset_location.name),
    create_asset_location.code, coalesce(create_asset_location.address, '{}'::jsonb), create_asset_location.latitude,
    create_asset_location.longitude, coalesce(create_asset_location.metadata, '{}'::jsonb))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_asset_location"(uuid, text, text, uuid, text, jsonb, double precision, double precision, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_asset_location"(uuid, text, text, uuid, text, jsonb, double precision, double precision, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, parentId, code, address,
-- latitude, longitude, area and metadata. A null value clears an optional key.
create or replace function "better_supabase"."update_asset_location"(location_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."asset_locations" x where x."id" = update_asset_location.location_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_asset_location.patch) is distinct from 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'ASSETS_PATCH_INVALID';
  end if;
  if update_asset_location.patch ? 'area' and jsonb_typeof(update_asset_location.patch -> 'area') <> 'null' then
    raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
  end if;
  if update_asset_location.patch ? 'code' and update_asset_location.patch ->> 'code' is not null and exists (
    select 1 from "better_supabase"."asset_locations" x where x."tenant_id" = v_row."tenant_id" and x."code" = update_asset_location.patch ->> 'code' and x."id" <> v_row."id"
  ) then
    raise exception 'a location with this code already exists' using errcode = '23505', hint = 'ASSETS_CODE_TAKEN';
  end if;
  update "better_supabase"."asset_locations" x set
    "kind" = case when update_asset_location.patch ? 'kind' then update_asset_location.patch ->> 'kind' else x."kind" end,
    "name" = case when update_asset_location.patch ? 'name' then trim(update_asset_location.patch ->> 'name') else x."name" end,
    "parent_id" = case when update_asset_location.patch ? 'parentId' then (update_asset_location.patch ->> 'parentId')::uuid else x."parent_id" end,
    "code" = case when update_asset_location.patch ? 'code' then update_asset_location.patch ->> 'code' else x."code" end,
    "address" = case when update_asset_location.patch ? 'address' then coalesce(nullif(update_asset_location.patch -> 'address', 'null'::jsonb), '{}'::jsonb) else x."address" end,
    "latitude" = case when update_asset_location.patch ? 'latitude' then (update_asset_location.patch ->> 'latitude')::double precision else x."latitude" end,
    "longitude" = case when update_asset_location.patch ? 'longitude' then (update_asset_location.patch ->> 'longitude')::double precision else x."longitude" end,
    "metadata" = case when update_asset_location.patch ? 'metadata' then coalesce(nullif(update_asset_location.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x."metadata" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_asset_location"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_asset_location"(uuid, jsonb) to authenticated, service_role;

-- Archives a location with no open sublocations and no assets in service.
create or replace function "better_supabase"."archive_asset_location"(location_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."asset_locations" x where x."id" = archive_asset_location.location_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."asset_locations" y where y."parent_id" = v_row."id" and y."archived_at" is null)
    or exists (select 1 from "better_supabase"."assets" y where y."location_id" = v_row."id" and y."status" <> 'retired') then
    raise exception 'move or archive the sublocations and assets of this location first' using errcode = '55000', hint = 'ASSETS_LOCATION_IN_USE';
  end if;
  if v_row."archived_at" is null then
    update "better_supabase"."asset_locations" x set "archived_at" = now(), "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."archive_asset_location"(uuid) from public, anon;
grant execute on function "better_supabase"."archive_asset_location"(uuid) to authenticated, service_role;

-- A location with its path from the top (path ends with the location itself)
-- and how many sublocations and assets it holds.
create or replace function "better_supabase"."get_asset_location"(location_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."asset_locations"%rowtype;
begin
  select * into v_row from "better_supabase"."asset_locations" x where x."id" = get_asset_location.location_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'path', coalesce((
    with recursive up as (
      select y."id" as id, y."parent_id" as parent, y."kind" as kind, y."name" as name, 0 as depth from "better_supabase"."asset_locations" y where y."id" = v_row."id"
      union all
      select y."id", y."parent_id", y."kind", y."name", up.depth + 1 from "better_supabase"."asset_locations" y join up on y."id" = up.parent where up.depth < 64
    )
    select jsonb_agg(jsonb_build_object('id', up.id, 'kind', up.kind, 'name', up.name) order by up.depth desc) from up
  ), '[]'::jsonb),
    'locations', (select count(*)::integer from "better_supabase"."asset_locations" y where y."parent_id" = v_row."id" and y."archived_at" is null),
    'assets', (select count(*)::integer from "better_supabase"."assets" y where y."location_id" = v_row."id" and y."status" <> 'retired'));
end;
$$;
revoke execute on function "better_supabase"."get_asset_location"(uuid) from public, anon;
grant execute on function "better_supabase"."get_asset_location"(uuid) to authenticated, service_role;

-- The locations directly under parent_id, or the top ones when it is null.
create or replace function "better_supabase"."list_asset_locations"(tenant uuid, parent_id uuid default null, include_archived boolean default false, page_size integer default 200)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.name, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'parentId', x."parent_id", 'kind', x."kind", 'name', x."name", 'code', x."code", 'address', x."address", 'latitude', x."latitude", 'longitude', x."longitude", 'area', null::jsonb, 'metadata', x."metadata", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."name" as name, x."id" as id
    from "better_supabase"."asset_locations" x
    where x."tenant_id" = list_asset_locations.tenant
      and x."parent_id" is not distinct from list_asset_locations.parent_id
      and (coalesce(list_asset_locations.include_archived, false) or x."archived_at" is null)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false))
    order by x."name", x."id"
    limit least(greatest(coalesce(list_asset_locations.page_size, 200), 1), 1000)
  ) z
$$;
revoke execute on function "better_supabase"."list_asset_locations"(uuid, uuid, boolean, integer) from public, anon;
grant execute on function "better_supabase"."list_asset_locations"(uuid, uuid, boolean, integer) to authenticated, service_role;

-- Registers an asset, at location_id when given.
create or replace function "better_supabase"."create_asset"(tenant uuid, kind text, name text, location_id uuid default null, tag text default null, serial_number text default null, latitude double precision default null, longitude double precision default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_asset.tenant, 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if create_asset.location_id is not null and not exists (
    select 1 from "better_supabase"."asset_locations" y where y."id" = create_asset.location_id and y."tenant_id" = create_asset.tenant and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if create_asset.tag is not null and exists (
    select 1 from "better_supabase"."assets" x where x."tenant_id" = create_asset.tenant and x."tag" = create_asset.tag
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  insert into "better_supabase"."assets" ("tenant_id", "location_id", "kind", "name", "tag", "serial_number", "latitude", "longitude", "metadata", "created_by")
  values (create_asset.tenant, create_asset.location_id, create_asset.kind, trim(create_asset.name), create_asset.tag,
    create_asset.serial_number, create_asset.latitude, create_asset.longitude, coalesce(create_asset.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) from public, anon;
grant execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, locationId, tag, serialNumber,
-- status, latitude, longitude and metadata. Retiring an asset releases it.
create or replace function "better_supabase"."update_asset"(asset_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
  v_location uuid;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = update_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_asset.patch) is distinct from 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'ASSETS_PATCH_INVALID';
  end if;
  v_location := case when update_asset.patch ? 'locationId' then (update_asset.patch ->> 'locationId')::uuid else v_row."location_id" end;
  if v_location is distinct from v_row."location_id" then
    if v_location is not null and not exists (
    select 1 from "better_supabase"."asset_locations" y where y."id" = v_location and y."tenant_id" = v_row."tenant_id" and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  end if;
  v_status := case when update_asset.patch ? 'status' then update_asset.patch ->> 'status' else v_row."status" end;
  if update_asset.patch ? 'tag' and update_asset.patch ->> 'tag' is not null and exists (
    select 1 from "better_supabase"."assets" x where x."tenant_id" = v_row."tenant_id" and x."tag" = update_asset.patch ->> 'tag' and x."id" <> v_row."id"
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  if v_status = 'retired' and v_row."status" <> 'retired' then
    update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  end if;
  update "better_supabase"."assets" x set
    "kind" = case when update_asset.patch ? 'kind' then update_asset.patch ->> 'kind' else x."kind" end,
    "name" = case when update_asset.patch ? 'name' then trim(update_asset.patch ->> 'name') else x."name" end,
    "location_id" = v_location,
    "tag" = case when update_asset.patch ? 'tag' then update_asset.patch ->> 'tag' else x."tag" end,
    "serial_number" = case when update_asset.patch ? 'serialNumber' then update_asset.patch ->> 'serialNumber' else x."serial_number" end,
    "status" = v_status,
    "latitude" = case when update_asset.patch ? 'latitude' then (update_asset.patch ->> 'latitude')::double precision else x."latitude" end,
    "longitude" = case when update_asset.patch ? 'longitude' then (update_asset.patch ->> 'longitude')::double precision else x."longitude" end,
    "metadata" = case when update_asset.patch ? 'metadata' then coalesce(nullif(update_asset.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x."metadata" end,
    "assignee_type" = case when v_status = 'retired' then null else x."assignee_type" end,
    "assignee_id" = case when v_status = 'retired' then null else x."assignee_id" end,
    "retired_at" = case when v_status = 'retired' then coalesce(x."retired_at", now()) else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_asset"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_asset"(uuid, jsonb) to authenticated, service_role;

-- Assigns an asset to a member (assignee_type member, a user id) or to a
-- record such as a party. The previous assignment ends.
create or replace function "better_supabase"."assign_asset"(asset_id uuid, assignee_type text, assignee_id text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = assign_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."status" = 'retired' then
    raise exception 'a retired asset can''t be assigned' using errcode = '55000', hint = 'ASSETS_RETIRED';
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
    raise exception 'an assignee needs a lowercase type and an id' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  if assign_asset.assignee_type = 'member' and (
    assign_asset.assignee_id !~ '^[0-9a-fA-F-]{36}$'
    or not coalesce(better_supabase.can_user(assign_asset.assignee_id::uuid, 'tenant', v_row."tenant_id", 'assets.read'), false)
  ) then
    raise exception 'the member can''t see this organization''s assets' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_asset_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using v_row."id", assign_asset.assignee_type, assign_asset.assignee_id;
    end if;
  end;
  update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  insert into "better_supabase"."asset_assignments" ("tenant_id", "asset_id", "assignee_type", "assignee_id", "note", "assigned_by")
  values (v_row."tenant_id", v_row."id", assign_asset.assignee_type, assign_asset.assignee_id, nullif(trim(assign_asset.note), ''), auth.uid());
  update "better_supabase"."assets" x set "assignee_type" = assign_asset.assignee_type, "assignee_id" = assign_asset.assignee_id, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_asset_assign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."assign_asset"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."assign_asset"(uuid, text, text, text) to authenticated, service_role;

-- Ends the asset's current assignment; a no-op when it has none.
create or replace function "better_supabase"."release_asset"(asset_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = release_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."assignee_type" is not null then
    update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
    update "better_supabase"."assets" x set "assignee_type" = null, "assignee_id" = null, "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."release_asset"(uuid) from public, anon;
grant execute on function "better_supabase"."release_asset"(uuid) to authenticated, service_role;

-- An asset with its location's path and the booking resources and open work
-- items that name it.
create or replace function "better_supabase"."get_asset"(asset_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  select * into v_row from "better_supabase"."assets" x where x."id" = get_asset.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'locationPath', case when v_row."location_id" is null then '[]'::jsonb else coalesce((
    with recursive up as (
      select y."id" as id, y."parent_id" as parent, y."kind" as kind, y."name" as name, 0 as depth from "better_supabase"."asset_locations" y where y."id" = v_row."location_id"
      union all
      select y."id", y."parent_id", y."kind", y."name", up.depth + 1 from "better_supabase"."asset_locations" y join up on y."id" = up.parent where up.depth < 64
    )
    select jsonb_agg(jsonb_build_object('id', up.id, 'kind', up.kind, 'name', up.name) order by up.depth desc) from up
  ), '[]'::jsonb) end,
    'links', jsonb_build_object('bookingResources', '[]'::jsonb, 'workItems', '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_asset"(uuid) from public, anon;
grant execute on function "better_supabase"."get_asset"(uuid) to authenticated, service_role;

-- Assets newest first. With location_id, include_sublocations also returns
-- the assets below it. With tenant null an assignee decides the organization.
create or replace function "better_supabase"."list_assets"(tenant uuid, location_id uuid default null, include_sublocations boolean default false, kind text default null, status text default null, assignee_type text default null, assignee_id text default null, query text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with recursive below as (
    select y."id" as id, 0 as depth from "better_supabase"."asset_locations" y where y."id" = list_assets.location_id
    union all
    select y."id", below.depth + 1 from "better_supabase"."asset_locations" y join below on y."parent_id" = below.id
    where coalesce(list_assets.include_sublocations, false) and below.depth < 64
  )
  select coalesce(jsonb_agg(z.item order by z.created_at desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created_at, x."id" as id
    from "better_supabase"."assets" x
    where (list_assets.tenant is null or x."tenant_id" = list_assets.tenant)
      and (list_assets.location_id is null or x."location_id" in (select below.id from below))
      and (list_assets.kind is null or x."kind" = list_assets.kind)
      and (list_assets.status is null or x."status" = list_assets.status)
      and (list_assets.assignee_type is null or x."assignee_type" = list_assets.assignee_type)
      and (list_assets.assignee_id is null or x."assignee_id" = list_assets.assignee_id)
      and (list_assets.query is null or x."name" ilike '%' || list_assets.query || '%' or x."tag" = list_assets.query or x."serial_number" = list_assets.query)
      and (list_assets.before is null or x."created_at" < list_assets.before)
      and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)) or (x."assignee_type" = 'member' and x."assignee_id" = auth.uid()::text))
    order by x."created_at" desc, x."id"
    limit least(greatest(coalesce(list_assets.page_size, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."list_assets"(uuid, uuid, boolean, text, text, text, text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_assets"(uuid, uuid, boolean, text, text, text, text, text, timestamptz, integer) to authenticated, service_role;

-- An asset's assignments, newest first.
create or replace function "better_supabase"."asset_assignment_history"(asset_id uuid, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  select * into v_row from "better_supabase"."assets" x where x."id" = asset_assignment_history.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return coalesce((
    select jsonb_agg(z.item order by z.assigned_at desc, z.id)
    from (
      select jsonb_build_object('id', y."id", 'assetId', y."asset_id", 'assigneeType', y."assignee_type", 'assigneeId', y."assignee_id", 'note', y."note", 'assignedBy', y."assigned_by", 'assignedAt', y."assigned_at", 'releasedAt', y."released_at") as item, y."assigned_at" as assigned_at, y."id" as id
      from "better_supabase"."asset_assignments" y where y."asset_id" = v_row."id"
      order by y."assigned_at" desc, y."id"
      limit least(greatest(coalesce(asset_assignment_history.page_size, 50), 1), 500)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."asset_assignment_history"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."asset_assignment_history"(uuid, integer) to authenticated, service_role;

-- The assets and locations within radius_meters of a point, nearest first,
-- each with distanceMeters. The haversine distance on latitude and longitude.
create or replace function "better_supabase"."assets_near"(tenant uuid, latitude double precision, longitude double precision, radius_meters double precision, kind text default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dlat double precision := assets_near.radius_meters / 111320.0;
  v_dlng double precision := assets_near.radius_meters / (111320.0 * greatest(cos(radians(assets_near.latitude)), 0.01));
  v_limit integer := least(greatest(coalesce(assets_near.page_size, 50), 1), 500);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assets_near.tenant, 'assets.read'), false)) then
    raise exception 'not allowed to read assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if assets_near.latitude is null or assets_near.longitude is null or assets_near.latitude not between -90 and 90 or assets_near.longitude not between -180 and 180 then
    raise exception 'latitude must be between -90 and 90 and longitude between -180 and 180' using errcode = '22023', hint = 'ASSETS_POINT_INVALID';
  end if;
  if assets_near.radius_meters is null or assets_near.radius_meters <= 0 or assets_near.radius_meters > 1000000 then
    raise exception 'radius_meters must be above 0 and at most 1000000' using errcode = '22023', hint = 'ASSETS_RADIUS_INVALID';
  end if;
  return jsonb_build_object(
    'assets', coalesce((
      select jsonb_agg(z.item || jsonb_build_object('distanceMeters', z.distance) order by z.distance, z.id)
      from (
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
        from "better_supabase"."assets" x
        where x."tenant_id" = assets_near.tenant and x."latitude" is not null and x."status" <> 'retired'
          and (assets_near.kind is null or x."kind" = assets_near.kind)
          and x."latitude" between assets_near.latitude - v_dlat and assets_near.latitude + v_dlat
        and x."longitude" between assets_near.longitude - v_dlng and assets_near.longitude + v_dlng
        and (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) <= assets_near.radius_meters
        order by 2, 3
        limit v_limit
      ) z
    ), '[]'::jsonb),
    'locations', coalesce((
      select jsonb_agg(z.item || jsonb_build_object('distanceMeters', z.distance) order by z.distance, z.id)
      from (
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'parentId', x."parent_id", 'kind', x."kind", 'name', x."name", 'code', x."code", 'address', x."address", 'latitude', x."latitude", 'longitude', x."longitude", 'area', null::jsonb, 'metadata', x."metadata", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
        from "better_supabase"."asset_locations" x
        where x."tenant_id" = assets_near.tenant and x."latitude" is not null and x."archived_at" is null
          and x."latitude" between assets_near.latitude - v_dlat and assets_near.latitude + v_dlat
        and x."longitude" between assets_near.longitude - v_dlng and assets_near.longitude + v_dlng
        and (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) <= assets_near.radius_meters
        order by 2, 3
        limit v_limit
      ) z
    ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."assets_near"(uuid, double precision, double precision, double precision, text, integer) from public, anon;
grant execute on function "better_supabase"."assets_near"(uuid, double precision, double precision, double precision, text, integer) to authenticated, service_role;

-- The locations whose area contains a point, smallest area first. Needs the
-- postgis option.
create or replace function "better_supabase"."asset_locations_at"(tenant uuid, latitude double precision, longitude double precision)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', asset_locations_at.tenant, 'assets.read'), false)) then
    raise exception 'not allowed to read assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
end;
$$;
revoke execute on function "better_supabase"."asset_locations_at"(uuid, double precision, double precision) from public, anon;
grant execute on function "better_supabase"."asset_locations_at"(uuid, double precision, double precision) to authenticated, service_role;

-- Names the asset a booking resource or a work item is about; a null
-- asset_id clears it. target_type is booking_resource or work_item.
create or replace function "better_supabase"."set_asset_link"(target_type text, target_id uuid, asset_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  raise exception 'install bookings or work-items to link assets' using errcode = '22023', hint = 'ASSETS_LINK_UNSUPPORTED';
end;
$$;
revoke execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) to authenticated, service_role;

-- blocks.assets.api: entry points for the Data API.
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

create or replace function "api"."create_asset_location"(tenant uuid, kind text, name text, parent_id uuid default null, code text default null, address jsonb default null, latitude double precision default null, longitude double precision default null, area jsonb default null, metadata jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_asset_location"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."create_asset_location"(uuid, text, text, uuid, text, jsonb, double precision, double precision, jsonb, jsonb) from public, anon;
grant execute on function "api"."create_asset_location"(uuid, text, text, uuid, text, jsonb, double precision, double precision, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."update_asset_location"(location_id uuid, patch jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_asset_location"($1, $2) $$;
revoke execute on function "api"."update_asset_location"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_asset_location"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."archive_asset_location"(location_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_asset_location"($1) $$;
revoke execute on function "api"."archive_asset_location"(uuid) from public, anon;
grant execute on function "api"."archive_asset_location"(uuid) to authenticated, service_role;

create or replace function "api"."get_asset_location"(location_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_asset_location"($1) $$;
revoke execute on function "api"."get_asset_location"(uuid) from public, anon;
grant execute on function "api"."get_asset_location"(uuid) to authenticated, service_role;

create or replace function "api"."list_asset_locations"(tenant uuid, parent_id uuid default null, include_archived boolean default false, page_size integer default 200)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_asset_locations"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_asset_locations"(uuid, uuid, boolean, integer) from public, anon;
grant execute on function "api"."list_asset_locations"(uuid, uuid, boolean, integer) to authenticated, service_role;

create or replace function "api"."create_asset"(tenant uuid, kind text, name text, location_id uuid default null, tag text default null, serial_number text default null, latitude double precision default null, longitude double precision default null, metadata jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_asset"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) from public, anon;
grant execute on function "api"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) to authenticated, service_role;

create or replace function "api"."update_asset"(asset_id uuid, patch jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_asset"($1, $2) $$;
revoke execute on function "api"."update_asset"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_asset"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."assign_asset"(asset_id uuid, assignee_type text, assignee_id text, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."assign_asset"($1, $2, $3, $4) $$;
revoke execute on function "api"."assign_asset"(uuid, text, text, text) from public, anon;
grant execute on function "api"."assign_asset"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."release_asset"(asset_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."release_asset"($1) $$;
revoke execute on function "api"."release_asset"(uuid) from public, anon;
grant execute on function "api"."release_asset"(uuid) to authenticated, service_role;

create or replace function "api"."get_asset"(asset_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_asset"($1) $$;
revoke execute on function "api"."get_asset"(uuid) from public, anon;
grant execute on function "api"."get_asset"(uuid) to authenticated, service_role;

create or replace function "api"."list_assets"(tenant uuid, location_id uuid default null, include_sublocations boolean default false, kind text default null, status text default null, assignee_type text default null, assignee_id text default null, query text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_assets"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."list_assets"(uuid, uuid, boolean, text, text, text, text, text, timestamptz, integer) from public, anon;
grant execute on function "api"."list_assets"(uuid, uuid, boolean, text, text, text, text, text, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."asset_assignment_history"(asset_id uuid, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."asset_assignment_history"($1, $2) $$;
revoke execute on function "api"."asset_assignment_history"(uuid, integer) from public, anon;
grant execute on function "api"."asset_assignment_history"(uuid, integer) to authenticated, service_role;

create or replace function "api"."assets_near"(tenant uuid, latitude double precision, longitude double precision, radius_meters double precision, kind text default null, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."assets_near"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."assets_near"(uuid, double precision, double precision, double precision, text, integer) from public, anon;
grant execute on function "api"."assets_near"(uuid, double precision, double precision, double precision, text, integer) to authenticated, service_role;

create or replace function "api"."asset_locations_at"(tenant uuid, latitude double precision, longitude double precision)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."asset_locations_at"($1, $2, $3) $$;
revoke execute on function "api"."asset_locations_at"(uuid, double precision, double precision) from public, anon;
grant execute on function "api"."asset_locations_at"(uuid, double precision, double precision) to authenticated, service_role;

create or replace function "api"."set_asset_link"(target_type text, target_id uuid, asset_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_asset_link"($1, $2, $3) $$;
revoke execute on function "api"."set_asset_link"(text, uuid, uuid) from public, anon;
grant execute on function "api"."set_asset_link"(text, uuid, uuid) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_113_assets.sql
-- better-supabase module: assets
-- @bs-module-data assets
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
