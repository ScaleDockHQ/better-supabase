-- ==== alone: schema supabase/schemas/900_better_supabase_114_assets.sql
-- better-supabase module: assets
-- @bsb-block assets@1 managed
-- @bsb-hash sha256:969d3e782634dc0eaaea71bb915efb504d11da3f0ba5606a5b780d2c97eaa5f8
-- A location hierarchy (site, building, unit) and an asset registry with tags, status, coordinates and assignment to members or records. Optional PostGIS stores points and areas as geography; bookings resources and work items can name an asset.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_locations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_depreciations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
create index if not exists "asset_locations_parent_idx" on "better_supabase"."asset_locations" ("parent_id", "tenant_id");
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
  "assignee_type" text check ("assignee_type" is null or "assignee_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
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
create index if not exists "assets_location_idx" on "better_supabase"."assets" ("location_id", "tenant_id");
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
revoke all on "better_supabase"."asset_locations" from public, anon, authenticated;
grant select on "better_supabase"."asset_locations" to authenticated;
grant all on "better_supabase"."asset_locations" to service_role;
drop policy if exists asset_locations_read on "better_supabase"."asset_locations";
create policy asset_locations_read on "better_supabase"."asset_locations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));
alter table "better_supabase"."assets" enable row level security;
revoke all on "better_supabase"."assets" from public, anon, authenticated;
grant select on "better_supabase"."assets" to authenticated;
grant all on "better_supabase"."assets" to service_role;
drop policy if exists assets_read on "better_supabase"."assets";
create policy assets_read on "better_supabase"."assets"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text));
alter table "better_supabase"."asset_assignments" enable row level security;
revoke all on "better_supabase"."asset_assignments" from public, anon, authenticated;
grant select on "better_supabase"."asset_assignments" to authenticated;
grant all on "better_supabase"."asset_assignments" to service_role;
drop policy if exists asset_assignments_read on "better_supabase"."asset_assignments";
create policy asset_assignments_read on "better_supabase"."asset_assignments"
  for select to authenticated
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
drop trigger if exists "bsb_asset_locations_parent" on "better_supabase"."asset_locations";
create trigger "bsb_asset_locations_parent" before insert or update of "parent_id" on "better_supabase"."asset_locations"
  for each row execute function "better_supabase"."asset_location_check_parent"();

-- What an asset cost and how it depreciates, in bigint minor units of currency.
alter table "better_supabase"."assets" add column if not exists "acquisition_cost" bigint check ("acquisition_cost" >= 0);
alter table "better_supabase"."assets" add column if not exists "currency" text check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."assets" add column if not exists "acquired_on" date;
alter table "better_supabase"."assets" add column if not exists "useful_life_months" integer check ("useful_life_months" between 1 and 1200);
alter table "better_supabase"."assets" add column if not exists "residual_value" bigint not null default 0 check ("residual_value" >= 0);
alter table "better_supabase"."assets" add column if not exists "depreciation_method" text not null default 'none' check ("depreciation_method" in ('none', 'straight_line', 'declining_balance'));
-- Declining balance: the yearly rate in basis points of the book value.
alter table "better_supabase"."assets" add column if not exists "depreciation_rate_bps" integer check ("depreciation_rate_bps" between 1 and 100000);
alter table "better_supabase"."assets" add column if not exists "disposed_on" date;
alter table "better_supabase"."assets" add column if not exists "disposal_amount" bigint check ("disposal_amount" >= 0);

-- One month of an asset's depreciation; entry_id is its accounting entry.
create table if not exists "better_supabase"."asset_depreciations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "asset_id" uuid not null references "better_supabase"."assets" ("id") on delete cascade,
  "period_start" date not null check (extract(day from "period_start") = 1),
  "amount" bigint not null check ("amount" > 0),
  "entry_id" uuid,
  "created_at" timestamptz not null default now(),
  unique ("asset_id", "period_start")
);
create index if not exists "asset_depreciations_tenant_idx" on "better_supabase"."asset_depreciations" ("tenant_id", "period_start");
alter table "better_supabase"."asset_depreciations" enable row level security;
revoke all on "better_supabase"."asset_depreciations" from public, anon, authenticated;
grant select on "better_supabase"."asset_depreciations" to authenticated;
grant all on "better_supabase"."asset_depreciations" to service_role;
drop policy if exists asset_depreciations_read on "better_supabase"."asset_depreciations";
create policy asset_depreciations_read on "better_supabase"."asset_depreciations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));



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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
end;
$$;
revoke execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) from public, anon;
grant execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, locationId, tag, serialNumber,
-- status, latitude, longitude and metadata, and the book value keys
-- acquisitionCost, currency, acquiredOn, usefulLifeMonths, residualValue,
-- depreciationMethod and depreciationRateBps. Retiring an asset releases it.
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
  if v_row."disposed_on" is not null and (
    update_asset.patch ?| array['acquisitionCost', 'currency', 'acquiredOn', 'usefulLifeMonths', 'residualValue', 'depreciationMethod', 'depreciationRateBps'] or coalesce(update_asset.patch ->> 'status', 'retired') <> 'retired'
  ) then
    raise exception 'a disposed asset stays retired and its book value can''t change' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if update_asset.patch ? 'currency' and not update_asset.patch ? 'acquisitionCost' and v_row."acquisition_cost" is not null
    and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency" then
    raise exception 'the amounts are in another currency than the asset''s cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if (
    (update_asset.patch ? 'acquisitionCost' and (update_asset.patch ->> 'acquisitionCost')::bigint is distinct from v_row."acquisition_cost")
    or (update_asset.patch ? 'currency' and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency")
    or (update_asset.patch ? 'acquiredOn' and (update_asset.patch ->> 'acquiredOn')::date is distinct from v_row."acquired_on")
  ) and exists (
    select 1 from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
  ) then
    raise exception 'the cost, currency and acquisition date are fixed once the asset has depreciated' using errcode = '55000', hint = 'ASSETS_DEPRECIATION_STARTED';
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
    "acquisition_cost" = case when update_asset.patch ? 'acquisitionCost' then (update_asset.patch ->> 'acquisitionCost')::bigint else x."acquisition_cost" end,
    "currency" = case when update_asset.patch ? 'currency' then upper(update_asset.patch ->> 'currency') else x."currency" end,
    "acquired_on" = case when update_asset.patch ? 'acquiredOn' then (update_asset.patch ->> 'acquiredOn')::date else x."acquired_on" end,
    "useful_life_months" = case when update_asset.patch ? 'usefulLifeMonths' then (update_asset.patch ->> 'usefulLifeMonths')::integer else x."useful_life_months" end,
    "residual_value" = case when update_asset.patch ? 'residualValue' then coalesce((update_asset.patch ->> 'residualValue')::bigint, 0) else x."residual_value" end,
    "depreciation_method" = case when update_asset.patch ? 'depreciationMethod' then coalesce(update_asset.patch ->> 'depreciationMethod', 'none') else x."depreciation_method" end,
    "depreciation_rate_bps" = case when update_asset.patch ? 'depreciationRateBps' then (update_asset.patch ->> 'depreciationRateBps')::integer else x."depreciation_rate_bps" end,
    "assignee_type" = case when v_status = 'retired' then null else x."assignee_type" end,
    "assignee_id" = case when v_status = 'retired' then null else x."assignee_id" end,
    "retired_at" = case when v_status = 'retired' then coalesce(x."retired_at", now()) else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."acquisition_cost" is not null and v_row."currency" is null then
    raise exception 'an acquisition cost needs a currency' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."residual_value" > coalesce(v_row."acquisition_cost", 0) and v_row."depreciation_method" <> 'none' then
    raise exception 'the residual value is more than the acquisition cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" <> 'none' and (v_row."acquisition_cost" is null or v_row."acquired_on" is null) then
    raise exception 'depreciation needs an acquisition cost and date' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'straight_line' and v_row."useful_life_months" is null then
    raise exception 'straight-line depreciation needs a useful life' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'declining_balance' and v_row."depreciation_rate_bps" is null then
    raise exception 'declining-balance depreciation needs a rate' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."status" = 'retired' then
    raise exception 'a retired asset can''t be assigned' using errcode = '55000', hint = 'ASSETS_RETIRED';
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_-]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text) || (select jsonb_build_object('accumulatedDepreciation', q.total::text, 'bookValue', case when v_row."acquisition_cost" is null then null else (v_row."acquisition_cost" - q.total)::text end) from (select coalesce(sum(y."amount"), 0) as total from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id") q) || jsonb_build_object(
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
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, x."created_at" as created_at, x."id" as id
    from "better_supabase"."assets" x
    where (list_assets.tenant is null or x."tenant_id" = list_assets.tenant)
      and (list_assets.location_id is null or x."location_id" in (select below.id from below))
      and (list_assets.kind is null or x."kind" = list_assets.kind)
      and (list_assets.status is null or x."status" = list_assets.status)
      and (list_assets.assignee_type is null or x."assignee_type" = list_assets.assignee_type)
      and (list_assets.assignee_id is null or x."assignee_id" = list_assets.assignee_id)
      and (list_assets.query is null or x."name" ilike '%' || list_assets.query || '%' or x."tag" = list_assets.query or x."serial_number" = list_assets.query)
      and (list_assets.before is null or x."created_at" < list_assets.before)
      and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)) or (x."assignee_type" = 'member' and coalesce(x."assignee_id" = auth.uid()::text, false)))
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
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
  raise exception 'install bookings or tasks to link assets' using errcode = '22023', hint = 'ASSETS_LINK_UNSUPPORTED';
end;
$$;
revoke execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) to authenticated, service_role;


-- Books an asset's depreciation for every month that ended on or before
-- until, from the month it was acquired in and stopping at the month it was
-- disposed of in. Straight line spreads the cost less the residual value over
-- the useful life; declining balance takes the yearly rate of the book value,
-- and writes the rest down at the end of the useful life when there is one.
-- A month books what the method has reached less what is booked, so a changed
-- life or residual value catches up in the next month. Returns the months
-- booked.
create or replace function "better_supabase"."asset_depreciate"(asset_id uuid, until date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_asset "better_supabase"."assets"%rowtype;
  v_row "better_supabase"."asset_depreciations"%rowtype;
  v_start date;
  v_month date;
  v_last date;
  v_booked bigint;
  v_base bigint;
  v_age integer;
  v_amount bigint;
  v_count integer := 0;
begin
  select * into v_asset from "better_supabase"."assets" x where x."id" = asset_depreciate.asset_id for update;
  if not found or v_asset."depreciation_method" = 'none'
    or v_asset."acquisition_cost" is null or v_asset."acquired_on" is null then
    return 0;
  end if;
  select max(y."period_start"), coalesce(sum(y."amount"), 0) into v_last, v_booked
  from "better_supabase"."asset_depreciations" y where y."asset_id" = v_asset."id";
  v_start := date_trunc('month', v_asset."acquired_on")::date;
  v_month := coalesce((v_last + interval '1 month')::date, v_start);
  v_base := v_asset."acquisition_cost" - v_asset."residual_value";
  while (v_month + interval '1 month' - interval '1 day')::date <= asset_depreciate.until
    and (v_asset."disposed_on" is null or v_month < date_trunc('month', v_asset."disposed_on")::date)
    and v_booked < v_base loop
    v_age := ((extract(year from v_month) - extract(year from v_start)) * 12 + extract(month from v_month) - extract(month from v_start))::integer + 1;
    if v_asset."depreciation_method" = 'straight_line' then
      v_amount := least(v_base, round(v_base::numeric * v_age / v_asset."useful_life_months")::bigint) - v_booked;
    elsif v_asset."useful_life_months" is not null and v_age >= v_asset."useful_life_months" then
      v_amount := v_base - v_booked;
    else
      v_amount := least(v_base - v_booked, round((v_asset."acquisition_cost" - v_booked)::numeric * v_asset."depreciation_rate_bps" / 120000)::bigint);
    end if;
    if v_amount > 0 then
      insert into "better_supabase"."asset_depreciations" ("tenant_id", "asset_id", "period_start", "amount")
      values (v_asset."tenant_id", v_asset."id", v_month, v_amount)
      returning * into v_row;
      null;
      v_booked := v_booked + v_amount;
      v_count := v_count + 1;
    end if;
    v_month := (v_month + interval '1 month')::date;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."asset_depreciate"(uuid, date) from public, anon, authenticated;

-- Books depreciation up to until (default today) for every asset in service
-- of an organization, or of every organization with tenant null. Run it
-- monthly from a scheduled job; it books each month once.
create or replace function "better_supabase"."run_asset_depreciation"(tenant uuid default null, until date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_until date := coalesce(run_asset_depreciation.until, current_date);
  v_id uuid;
  v_months integer;
  v_assets integer := 0;
  v_total integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role runs depreciation' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  for v_id in
    select x."id" from "better_supabase"."assets" x
    where (run_asset_depreciation.tenant is null or x."tenant_id" = run_asset_depreciation.tenant)
      and x."depreciation_method" <> 'none' and x."disposed_on" is null
    order by x."tenant_id", x."id"
  loop
    v_months := "better_supabase"."asset_depreciate"(v_id, v_until);
    if v_months > 0 then
      v_assets := v_assets + 1;
      v_total := v_total + v_months;
    end if;
  end loop;
  return jsonb_build_object('until', v_until, 'assets', v_assets, 'months', v_total);
end;
$$;
revoke execute on function "better_supabase"."run_asset_depreciation"(uuid, date) from public, anon, authenticated;
grant execute on function "better_supabase"."run_asset_depreciation"(uuid, date) to service_role;

-- Takes an asset off the books on disposed_on for amount, the proceeds in
-- currency (the asset's): books depreciation through the month before, then
-- retires and releases the asset and books the disposal, the proceeds less
-- the book value being a gain or a loss.
create or replace function "better_supabase"."dispose_asset"(asset_id uuid, disposed_on date, amount bigint default 0, currency text default null)
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
  select * into v_row from "better_supabase"."assets" x where x."id" = dispose_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."disposed_on" is not null then
    raise exception 'the asset is already disposed of' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if dispose_asset.disposed_on is null or coalesce(dispose_asset.amount, 0) < 0
    or dispose_asset.disposed_on < coalesce(v_row."acquired_on", dispose_asset.disposed_on) then
    raise exception 'a disposal needs a date on or after the acquisition and proceeds of 0 or more' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  if coalesce(dispose_asset.amount, 0) > 0 and (
    v_row."currency" is null or upper(coalesce(dispose_asset.currency, v_row."currency")) <> v_row."currency"
  ) then
    raise exception 'the proceeds need to be in the asset''s currency' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  perform "better_supabase"."asset_depreciate"(v_row."id", (date_trunc('month', dispose_asset.disposed_on) - interval '1 day')::date);
  update "better_supabase"."asset_assignments" y set "released_at" = now()
  where y."asset_id" = v_row."id" and y."released_at" is null;
  update "better_supabase"."assets" x set
    "disposed_on" = dispose_asset.disposed_on,
    "disposal_amount" = coalesce(dispose_asset.amount, 0),
    "status" = 'retired',
    "assignee_type" = null,
    "assignee_id" = null,
    "retired_at" = coalesce(x."retired_at", now()),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return "better_supabase"."get_asset"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."dispose_asset"(uuid, date, bigint, text) from public, anon;
grant execute on function "better_supabase"."dispose_asset"(uuid, date, bigint, text) to authenticated, service_role;

-- An asset's depreciation, oldest month first.
create or replace function "better_supabase"."list_asset_depreciations"(asset_id uuid, page_size integer default 600)
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
  select * into v_row from "better_supabase"."assets" x where x."id" = list_asset_depreciations.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'assetId', q."asset_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', v_row."currency", 'entryId', q."entry_id", 'createdAt', q."created_at") order by q."period_start"), '[]'::jsonb)
    from (
      select * from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
      order by y."period_start"
      limit greatest(1, least(coalesce(list_asset_depreciations.page_size, 600), 1200))
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_asset_depreciations"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_asset_depreciations"(uuid, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_locations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_select on "better_supabase"."asset_locations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_locations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_update on "better_supabase"."asset_locations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_locations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."assets";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."assets";
create policy bsb_tenant_scope_select on "better_supabase"."assets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assets";
create policy bsb_tenant_scope_insert on "better_supabase"."assets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."assets";
create policy bsb_tenant_scope_update on "better_supabase"."assets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assets";
create policy bsb_tenant_scope_delete on "better_supabase"."assets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."asset_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("asset_id" in (select y."id" from "better_supabase"."assets" y))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."asset_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_depreciations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_select on "better_supabase"."asset_depreciations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_depreciations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_update on "better_supabase"."asset_depreciations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_depreciations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_114_assets.sql
-- better-supabase module: assets
-- @bsb-block-data assets
-- @bsb-hash sha256:cdfee733cdb1ab16291963d28940f13d8d33a1ba53dbbfb6af72eed615bd1cdf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_114_assets.sql
-- better-supabase module: assets
-- @bsb-block assets@1 managed
-- @bsb-hash sha256:f444b2a815e9c2580d8d50df9aa6b4d39d0dd7954b5484547fad654d3085d539
-- A location hierarchy (site, building, unit) and an asset registry with tags, status, coordinates and assignment to members or records. Optional PostGIS stores points and areas as geography; bookings resources and work items can name an asset.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_locations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_depreciations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
create index if not exists "asset_locations_parent_idx" on "better_supabase"."asset_locations" ("parent_id", "tenant_id");
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
  "assignee_type" text check ("assignee_type" is null or "assignee_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
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
create index if not exists "assets_location_idx" on "better_supabase"."assets" ("location_id", "tenant_id");
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
revoke all on "better_supabase"."asset_locations" from public, anon, authenticated;
grant select on "better_supabase"."asset_locations" to authenticated;
grant all on "better_supabase"."asset_locations" to service_role;
drop policy if exists asset_locations_read on "better_supabase"."asset_locations";
create policy asset_locations_read on "better_supabase"."asset_locations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));
alter table "better_supabase"."assets" enable row level security;
revoke all on "better_supabase"."assets" from public, anon, authenticated;
grant select on "better_supabase"."assets" to authenticated;
grant all on "better_supabase"."assets" to service_role;
drop policy if exists assets_read on "better_supabase"."assets";
create policy assets_read on "better_supabase"."assets"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text));
alter table "better_supabase"."asset_assignments" enable row level security;
revoke all on "better_supabase"."asset_assignments" from public, anon, authenticated;
grant select on "better_supabase"."asset_assignments" to authenticated;
grant all on "better_supabase"."asset_assignments" to service_role;
drop policy if exists asset_assignments_read on "better_supabase"."asset_assignments";
create policy asset_assignments_read on "better_supabase"."asset_assignments"
  for select to authenticated
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
drop trigger if exists "bsb_asset_locations_parent" on "better_supabase"."asset_locations";
create trigger "bsb_asset_locations_parent" before insert or update of "parent_id" on "better_supabase"."asset_locations"
  for each row execute function "better_supabase"."asset_location_check_parent"();

-- What an asset cost and how it depreciates, in bigint minor units of currency.
alter table "better_supabase"."assets" add column if not exists "acquisition_cost" bigint check ("acquisition_cost" >= 0);
alter table "better_supabase"."assets" add column if not exists "currency" text check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."assets" add column if not exists "acquired_on" date;
alter table "better_supabase"."assets" add column if not exists "useful_life_months" integer check ("useful_life_months" between 1 and 1200);
alter table "better_supabase"."assets" add column if not exists "residual_value" bigint not null default 0 check ("residual_value" >= 0);
alter table "better_supabase"."assets" add column if not exists "depreciation_method" text not null default 'none' check ("depreciation_method" in ('none', 'straight_line', 'declining_balance'));
-- Declining balance: the yearly rate in basis points of the book value.
alter table "better_supabase"."assets" add column if not exists "depreciation_rate_bps" integer check ("depreciation_rate_bps" between 1 and 100000);
alter table "better_supabase"."assets" add column if not exists "disposed_on" date;
alter table "better_supabase"."assets" add column if not exists "disposal_amount" bigint check ("disposal_amount" >= 0);

-- One month of an asset's depreciation; entry_id is its accounting entry.
create table if not exists "better_supabase"."asset_depreciations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "asset_id" uuid not null references "better_supabase"."assets" ("id") on delete cascade,
  "period_start" date not null check (extract(day from "period_start") = 1),
  "amount" bigint not null check ("amount" > 0),
  "entry_id" uuid,
  "created_at" timestamptz not null default now(),
  unique ("asset_id", "period_start")
);
create index if not exists "asset_depreciations_tenant_idx" on "better_supabase"."asset_depreciations" ("tenant_id", "period_start");
alter table "better_supabase"."asset_depreciations" enable row level security;
revoke all on "better_supabase"."asset_depreciations" from public, anon, authenticated;
grant select on "better_supabase"."asset_depreciations" to authenticated;
grant all on "better_supabase"."asset_depreciations" to service_role;
drop policy if exists asset_depreciations_read on "better_supabase"."asset_depreciations";
create policy asset_depreciations_read on "better_supabase"."asset_depreciations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));

alter table "better_supabase"."booking_resources" add column if not exists asset_id uuid references "better_supabase"."assets" ("id") on delete set null;
create index if not exists "booking_resources_asset_idx" on "better_supabase"."booking_resources" (asset_id) where asset_id is not null;
alter table "better_supabase"."tasks" add column if not exists asset_id uuid references "better_supabase"."assets" ("id") on delete set null;
create index if not exists "tasks_asset_idx" on "better_supabase"."tasks" (asset_id) where asset_id is not null;

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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
end;
$$;
revoke execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) from public, anon;
grant execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, locationId, tag, serialNumber,
-- status, latitude, longitude and metadata, and the book value keys
-- acquisitionCost, currency, acquiredOn, usefulLifeMonths, residualValue,
-- depreciationMethod and depreciationRateBps. Retiring an asset releases it.
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
  if v_row."disposed_on" is not null and (
    update_asset.patch ?| array['acquisitionCost', 'currency', 'acquiredOn', 'usefulLifeMonths', 'residualValue', 'depreciationMethod', 'depreciationRateBps'] or coalesce(update_asset.patch ->> 'status', 'retired') <> 'retired'
  ) then
    raise exception 'a disposed asset stays retired and its book value can''t change' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if update_asset.patch ? 'currency' and not update_asset.patch ? 'acquisitionCost' and v_row."acquisition_cost" is not null
    and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency" then
    raise exception 'the amounts are in another currency than the asset''s cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if (
    (update_asset.patch ? 'acquisitionCost' and (update_asset.patch ->> 'acquisitionCost')::bigint is distinct from v_row."acquisition_cost")
    or (update_asset.patch ? 'currency' and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency")
    or (update_asset.patch ? 'acquiredOn' and (update_asset.patch ->> 'acquiredOn')::date is distinct from v_row."acquired_on")
  ) and exists (
    select 1 from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
  ) then
    raise exception 'the cost, currency and acquisition date are fixed once the asset has depreciated' using errcode = '55000', hint = 'ASSETS_DEPRECIATION_STARTED';
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
    "acquisition_cost" = case when update_asset.patch ? 'acquisitionCost' then (update_asset.patch ->> 'acquisitionCost')::bigint else x."acquisition_cost" end,
    "currency" = case when update_asset.patch ? 'currency' then upper(update_asset.patch ->> 'currency') else x."currency" end,
    "acquired_on" = case when update_asset.patch ? 'acquiredOn' then (update_asset.patch ->> 'acquiredOn')::date else x."acquired_on" end,
    "useful_life_months" = case when update_asset.patch ? 'usefulLifeMonths' then (update_asset.patch ->> 'usefulLifeMonths')::integer else x."useful_life_months" end,
    "residual_value" = case when update_asset.patch ? 'residualValue' then coalesce((update_asset.patch ->> 'residualValue')::bigint, 0) else x."residual_value" end,
    "depreciation_method" = case when update_asset.patch ? 'depreciationMethod' then coalesce(update_asset.patch ->> 'depreciationMethod', 'none') else x."depreciation_method" end,
    "depreciation_rate_bps" = case when update_asset.patch ? 'depreciationRateBps' then (update_asset.patch ->> 'depreciationRateBps')::integer else x."depreciation_rate_bps" end,
    "assignee_type" = case when v_status = 'retired' then null else x."assignee_type" end,
    "assignee_id" = case when v_status = 'retired' then null else x."assignee_id" end,
    "retired_at" = case when v_status = 'retired' then coalesce(x."retired_at", now()) else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."acquisition_cost" is not null and v_row."currency" is null then
    raise exception 'an acquisition cost needs a currency' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."residual_value" > coalesce(v_row."acquisition_cost", 0) and v_row."depreciation_method" <> 'none' then
    raise exception 'the residual value is more than the acquisition cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" <> 'none' and (v_row."acquisition_cost" is null or v_row."acquired_on" is null) then
    raise exception 'depreciation needs an acquisition cost and date' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'straight_line' and v_row."useful_life_months" is null then
    raise exception 'straight-line depreciation needs a useful life' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'declining_balance' and v_row."depreciation_rate_bps" is null then
    raise exception 'declining-balance depreciation needs a rate' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."status" = 'retired' then
    raise exception 'a retired asset can''t be assigned' using errcode = '55000', hint = 'ASSETS_RETIRED';
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_-]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text) || (select jsonb_build_object('accumulatedDepreciation', q.total::text, 'bookValue', case when v_row."acquisition_cost" is null then null else (v_row."acquisition_cost" - q.total)::text end) from (select coalesce(sum(y."amount"), 0) as total from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id") q) || jsonb_build_object(
    'locationPath', case when v_row."location_id" is null then '[]'::jsonb else coalesce((
    with recursive up as (
      select y."id" as id, y."parent_id" as parent, y."kind" as kind, y."name" as name, 0 as depth from "better_supabase"."asset_locations" y where y."id" = v_row."location_id"
      union all
      select y."id", y."parent_id", y."kind", y."name", up.depth + 1 from "better_supabase"."asset_locations" y join up on y."id" = up.parent where up.depth < 64
    )
    select jsonb_agg(jsonb_build_object('id', up.id, 'kind', up.kind, 'name', up.name) order by up.depth desc) from up
  ), '[]'::jsonb) end,
    'links', jsonb_build_object('bookingResources', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'name', y."name") order by y."name") from "better_supabase"."booking_resources" y where y.asset_id = v_row."id"), '[]'::jsonb), 'workItems', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'title', z.title) order by z.created_at desc) from (select y."id" as id, y."title" as title, y."created_at" as created_at from "better_supabase"."tasks" y where y.asset_id = v_row."id" and y."closed_at" is null order by y."created_at" desc limit 50) z), '[]'::jsonb)));
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
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, x."created_at" as created_at, x."id" as id
    from "better_supabase"."assets" x
    where (list_assets.tenant is null or x."tenant_id" = list_assets.tenant)
      and (list_assets.location_id is null or x."location_id" in (select below.id from below))
      and (list_assets.kind is null or x."kind" = list_assets.kind)
      and (list_assets.status is null or x."status" = list_assets.status)
      and (list_assets.assignee_type is null or x."assignee_type" = list_assets.assignee_type)
      and (list_assets.assignee_id is null or x."assignee_id" = list_assets.assignee_id)
      and (list_assets.query is null or x."name" ilike '%' || list_assets.query || '%' or x."tag" = list_assets.query or x."serial_number" = list_assets.query)
      and (list_assets.before is null or x."created_at" < list_assets.before)
      and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)) or (x."assignee_type" = 'member' and coalesce(x."assignee_id" = auth.uid()::text, false)))
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
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
  when 'task', 'work_item' then
    select y."tenant_id" into v_tenant from "better_supabase"."tasks" y where y."id" = set_asset_link.target_id;
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
  if set_asset_link.target_type in ('task', 'work_item') then
    update "better_supabase"."tasks" y set asset_id = set_asset_link.asset_id where y."id" = set_asset_link.target_id;
  end if;
  return jsonb_build_object('targetType', set_asset_link.target_type, 'targetId', set_asset_link.target_id, 'assetId', set_asset_link.asset_id);
end;
$$;
revoke execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) to authenticated, service_role;


-- Books an asset's depreciation for every month that ended on or before
-- until, from the month it was acquired in and stopping at the month it was
-- disposed of in. Straight line spreads the cost less the residual value over
-- the useful life; declining balance takes the yearly rate of the book value,
-- and writes the rest down at the end of the useful life when there is one.
-- A month books what the method has reached less what is booked, so a changed
-- life or residual value catches up in the next month. Returns the months
-- booked.
create or replace function "better_supabase"."asset_depreciate"(asset_id uuid, until date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_asset "better_supabase"."assets"%rowtype;
  v_row "better_supabase"."asset_depreciations"%rowtype;
  v_start date;
  v_month date;
  v_last date;
  v_booked bigint;
  v_base bigint;
  v_age integer;
  v_amount bigint;
  v_entry uuid;
  v_count integer := 0;
begin
  select * into v_asset from "better_supabase"."assets" x where x."id" = asset_depreciate.asset_id for update;
  if not found or v_asset."depreciation_method" = 'none'
    or v_asset."acquisition_cost" is null or v_asset."acquired_on" is null then
    return 0;
  end if;
  select max(y."period_start"), coalesce(sum(y."amount"), 0) into v_last, v_booked
  from "better_supabase"."asset_depreciations" y where y."asset_id" = v_asset."id";
  v_start := date_trunc('month', v_asset."acquired_on")::date;
  v_month := coalesce((v_last + interval '1 month')::date, v_start);
  v_base := v_asset."acquisition_cost" - v_asset."residual_value";
  while (v_month + interval '1 month' - interval '1 day')::date <= asset_depreciate.until
    and (v_asset."disposed_on" is null or v_month < date_trunc('month', v_asset."disposed_on")::date)
    and v_booked < v_base loop
    v_age := ((extract(year from v_month) - extract(year from v_start)) * 12 + extract(month from v_month) - extract(month from v_start))::integer + 1;
    if v_asset."depreciation_method" = 'straight_line' then
      v_amount := least(v_base, round(v_base::numeric * v_age / v_asset."useful_life_months")::bigint) - v_booked;
    elsif v_asset."useful_life_months" is not null and v_age >= v_asset."useful_life_months" then
      v_amount := v_base - v_booked;
    else
      v_amount := least(v_base - v_booked, round((v_asset."acquisition_cost" - v_booked)::numeric * v_asset."depreciation_rate_bps" / 120000)::bigint);
    end if;
    if v_amount > 0 then
      insert into "better_supabase"."asset_depreciations" ("tenant_id", "asset_id", "period_start", "amount")
      values (v_asset."tenant_id", v_asset."id", v_month, v_amount)
      returning * into v_row;
      v_entry := "better_supabase"."accounting_post_source"('asset_depreciation', v_row."id"::text);
      if v_entry is not null then
        update "better_supabase"."asset_depreciations" y set "entry_id" = v_entry where y."id" = v_row."id"
        returning * into v_row;
      end if;
      perform "better_supabase".emit_event('asset.depreciated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'assetId', v_row."asset_id", 'periodStart', v_row."period_start", 'amount', v_row."amount"::text, 'currency', v_asset."currency", 'entryId', v_row."entry_id"), 'assets/' || v_asset."id"::text, (v_asset."tenant_id")::text, null, 'better-supabase/assets');
      v_booked := v_booked + v_amount;
      v_count := v_count + 1;
    end if;
    v_month := (v_month + interval '1 month')::date;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."asset_depreciate"(uuid, date) from public, anon, authenticated;

-- Books depreciation up to until (default today) for every asset in service
-- of an organization, or of every organization with tenant null. Run it
-- monthly from a scheduled job; it books each month once.
create or replace function "better_supabase"."run_asset_depreciation"(tenant uuid default null, until date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_until date := coalesce(run_asset_depreciation.until, current_date);
  v_id uuid;
  v_months integer;
  v_assets integer := 0;
  v_total integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role runs depreciation' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  for v_id in
    select x."id" from "better_supabase"."assets" x
    where (run_asset_depreciation.tenant is null or x."tenant_id" = run_asset_depreciation.tenant)
      and x."depreciation_method" <> 'none' and x."disposed_on" is null
    order by x."tenant_id", x."id"
  loop
    v_months := "better_supabase"."asset_depreciate"(v_id, v_until);
    if v_months > 0 then
      v_assets := v_assets + 1;
      v_total := v_total + v_months;
    end if;
  end loop;
  return jsonb_build_object('until', v_until, 'assets', v_assets, 'months', v_total);
end;
$$;
revoke execute on function "better_supabase"."run_asset_depreciation"(uuid, date) from public, anon, authenticated;
grant execute on function "better_supabase"."run_asset_depreciation"(uuid, date) to service_role;

-- Takes an asset off the books on disposed_on for amount, the proceeds in
-- currency (the asset's): books depreciation through the month before, then
-- retires and releases the asset and books the disposal, the proceeds less
-- the book value being a gain or a loss.
create or replace function "better_supabase"."dispose_asset"(asset_id uuid, disposed_on date, amount bigint default 0, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
  v_entry uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = dispose_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."disposed_on" is not null then
    raise exception 'the asset is already disposed of' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if dispose_asset.disposed_on is null or coalesce(dispose_asset.amount, 0) < 0
    or dispose_asset.disposed_on < coalesce(v_row."acquired_on", dispose_asset.disposed_on) then
    raise exception 'a disposal needs a date on or after the acquisition and proceeds of 0 or more' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  if coalesce(dispose_asset.amount, 0) > 0 and (
    v_row."currency" is null or upper(coalesce(dispose_asset.currency, v_row."currency")) <> v_row."currency"
  ) then
    raise exception 'the proceeds need to be in the asset''s currency' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  perform "better_supabase"."asset_depreciate"(v_row."id", (date_trunc('month', dispose_asset.disposed_on) - interval '1 day')::date);
  update "better_supabase"."asset_assignments" y set "released_at" = now()
  where y."asset_id" = v_row."id" and y."released_at" is null;
  update "better_supabase"."assets" x set
    "disposed_on" = dispose_asset.disposed_on,
    "disposal_amount" = coalesce(dispose_asset.amount, 0),
    "status" = 'retired',
    "assignee_type" = null,
    "assignee_id" = null,
    "retired_at" = coalesce(x."retired_at", now()),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  v_entry := "better_supabase"."accounting_post_source"('asset_disposal', v_row."id"::text);
  perform "better_supabase".emit_event('asset.disposed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'disposedOn', v_row."disposed_on", 'amount', v_row."disposal_amount"::text, 'currency', v_row."currency", 'entryId', v_entry), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.disposed',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'disposed of asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'disposedOn', v_row."disposed_on", 'amount', v_row."disposal_amount"::text, 'currency', v_row."currency", 'entryId', v_entry)
  );
  return "better_supabase"."get_asset"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."dispose_asset"(uuid, date, bigint, text) from public, anon;
grant execute on function "better_supabase"."dispose_asset"(uuid, date, bigint, text) to authenticated, service_role;

-- An asset's depreciation, oldest month first.
create or replace function "better_supabase"."list_asset_depreciations"(asset_id uuid, page_size integer default 600)
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
  select * into v_row from "better_supabase"."assets" x where x."id" = list_asset_depreciations.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'assetId', q."asset_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', v_row."currency", 'entryId', q."entry_id", 'createdAt', q."created_at") order by q."period_start"), '[]'::jsonb)
    from (
      select * from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
      order by y."period_start"
      limit greatest(1, least(coalesce(list_asset_depreciations.page_size, 600), 1200))
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_asset_depreciations"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_asset_depreciations"(uuid, integer) to authenticated, service_role;


-- The entry of a month of an asset's depreciation for accounting:
-- depreciation expense against accumulated depreciation.
create or replace function "better_supabase"."accounting_asset_depreciation_lines"(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', y."tenant_id",
    'entryDate', (y."period_start" + interval '1 month' - interval '1 day')::date,
    'currency', a."currency",
    'reference', left(coalesce(a."tag" || ' ' || a."name", a."name"), 200),
    'memo', left('Depreciation of ' || a."name" || ' for ' || to_char(y."period_start", 'YYYY-MM'), 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'depreciation_expense', 'debit', y."amount"::text),
      jsonb_build_object('role', 'accumulated_depreciation', 'credit', y."amount"::text))
  )
  from "better_supabase"."asset_depreciations" y join "better_supabase"."assets" a on a."id" = y."asset_id"
  where y."id"::text = source_id
$$;
revoke execute on function "better_supabase"."accounting_asset_depreciation_lines"(text) from public, anon, authenticated;

-- The entry of an asset's disposal for accounting: the proceeds to bank and
-- the accumulated depreciation against the cost, the difference a gain or a loss.
create or replace function "better_supabase"."accounting_asset_disposal_lines"(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', a."tenant_id",
    'entryDate', a."disposed_on",
    'currency', a."currency",
    'reference', left(coalesce(a."tag" || ' ' || a."name", a."name"), 200),
    'memo', left('Disposal of ' || a."name", 500),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', a."disposal_amount"::text),
      jsonb_build_object('role', 'accumulated_depreciation', 'debit', q.total::text),
      jsonb_build_object('role', 'fixed_asset', 'credit', a."acquisition_cost"::text),
      jsonb_build_object('role', 'disposal_gain', 'credit', greatest(q.result, 0)::text),
      jsonb_build_object('role', 'disposal_loss', 'debit', greatest(-q.result, 0)::text))
  )
  from "better_supabase"."assets" a
  cross join lateral (
    select coalesce(sum(y."amount"), 0) as total,
      a."disposal_amount" + coalesce(sum(y."amount"), 0) - a."acquisition_cost" as result
    from "better_supabase"."asset_depreciations" y where y."asset_id" = a."id"
  ) q
  where a."id"::text = source_id and a."disposed_on" is not null and a."acquisition_cost" is not null
$$;
revoke execute on function "better_supabase"."accounting_asset_disposal_lines"(text) from public, anon, authenticated;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_locations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_select on "better_supabase"."asset_locations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_locations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_update on "better_supabase"."asset_locations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_locations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."assets";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."assets";
create policy bsb_tenant_scope_select on "better_supabase"."assets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assets";
create policy bsb_tenant_scope_insert on "better_supabase"."assets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."assets";
create policy bsb_tenant_scope_update on "better_supabase"."assets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assets";
create policy bsb_tenant_scope_delete on "better_supabase"."assets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."asset_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("asset_id" in (select y."id" from "better_supabase"."assets" y))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."asset_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_depreciations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_select on "better_supabase"."asset_depreciations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_depreciations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_update on "better_supabase"."asset_depreciations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_depreciations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
do $$
begin
  perform better_supabase.audit('better_supabase.assets', target_type => 'asset', event_prefix => 'asset', deferred => true);
  perform better_supabase.audit('better_supabase.asset_locations', target_type => 'asset_location', event_prefix => 'asset_location', deferred => true);
end;
$$;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_114_assets.sql
-- better-supabase module: assets
-- @bsb-block-data assets
-- @bsb-hash sha256:cdfee733cdb1ab16291963d28940f13d8d33a1ba53dbbfb6af72eed615bd1cdf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_114_assets.sql
-- better-supabase module: assets
-- @bsb-block assets@1 managed
-- @bsb-hash sha256:2b2bcd994f8fa14f7e4eb38e694353f35075a05a00e7c927516dbe5db7e5a4cf
-- A location hierarchy (site, building, unit) and an asset registry with tags, status, coordinates and assignment to members or records. Optional PostGIS stores points and areas as geography; bookings resources and work items can name an asset.
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
    drop policy if exists bsb_tenant_scope on "app_private"."asset_locations";
    drop policy if exists bsb_tenant_scope_select on "app_private"."asset_locations";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."asset_locations";
    drop policy if exists bsb_tenant_scope_update on "app_private"."asset_locations";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."asset_locations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."assets";
    drop policy if exists bsb_tenant_scope_select on "app_private"."assets";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."assets";
    drop policy if exists bsb_tenant_scope_update on "app_private"."assets";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."assets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."asset_assignments";
    drop policy if exists bsb_tenant_scope_select on "app_private"."asset_assignments";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."asset_assignments";
    drop policy if exists bsb_tenant_scope_update on "app_private"."asset_assignments";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."asset_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_select on "app_private"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_update on "app_private"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."asset_depreciations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
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
create index if not exists "asset_locations_parent_idx" on "app_private"."asset_locations" ("parent_id", "tenant_id");
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
  "assignee_type" text check ("assignee_type" is null or "assignee_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
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
create index if not exists "assets_location_idx" on "app_private"."assets" ("location_id", "tenant_id");
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
revoke all on "app_private"."asset_locations" from public, anon, authenticated;
grant select on "app_private"."asset_locations" to authenticated;
grant all on "app_private"."asset_locations" to service_role;
drop policy if exists asset_locations_read on "app_private"."asset_locations";
create policy asset_locations_read on "app_private"."asset_locations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));
alter table "app_private"."assets" enable row level security;
revoke all on "app_private"."assets" from public, anon, authenticated;
grant select on "app_private"."assets" to authenticated;
grant all on "app_private"."assets" to service_role;
drop policy if exists assets_read on "app_private"."assets";
create policy assets_read on "app_private"."assets"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text));
alter table "app_private"."asset_assignments" enable row level security;
revoke all on "app_private"."asset_assignments" from public, anon, authenticated;
grant select on "app_private"."asset_assignments" to authenticated;
grant all on "app_private"."asset_assignments" to service_role;
drop policy if exists asset_assignments_read on "app_private"."asset_assignments";
create policy asset_assignments_read on "app_private"."asset_assignments"
  for select to authenticated
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
drop trigger if exists "bsb_asset_locations_parent" on "app_private"."asset_locations";
create trigger "bsb_asset_locations_parent" before insert or update of "parent_id" on "app_private"."asset_locations"
  for each row execute function "app_private"."asset_location_check_parent"();

-- What an asset cost and how it depreciates, in bigint minor units of currency.
alter table "app_private"."assets" add column if not exists "acquisition_cost" bigint check ("acquisition_cost" >= 0);
alter table "app_private"."assets" add column if not exists "currency" text check ("currency" ~ '^[A-Z]{3}$');
alter table "app_private"."assets" add column if not exists "acquired_on" date;
alter table "app_private"."assets" add column if not exists "useful_life_months" integer check ("useful_life_months" between 1 and 1200);
alter table "app_private"."assets" add column if not exists "residual_value" bigint not null default 0 check ("residual_value" >= 0);
alter table "app_private"."assets" add column if not exists "depreciation_method" text not null default 'none' check ("depreciation_method" in ('none', 'straight_line', 'declining_balance'));
-- Declining balance: the yearly rate in basis points of the book value.
alter table "app_private"."assets" add column if not exists "depreciation_rate_bps" integer check ("depreciation_rate_bps" between 1 and 100000);
alter table "app_private"."assets" add column if not exists "disposed_on" date;
alter table "app_private"."assets" add column if not exists "disposal_amount" bigint check ("disposal_amount" >= 0);

-- One month of an asset's depreciation; entry_id is its accounting entry.
create table if not exists "app_private"."asset_depreciations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "asset_id" uuid not null references "app_private"."assets" ("id") on delete cascade,
  "period_start" date not null check (extract(day from "period_start") = 1),
  "amount" bigint not null check ("amount" > 0),
  "entry_id" uuid,
  "created_at" timestamptz not null default now(),
  unique ("asset_id", "period_start")
);
create index if not exists "asset_depreciations_tenant_idx" on "app_private"."asset_depreciations" ("tenant_id", "period_start");
alter table "app_private"."asset_depreciations" enable row level security;
revoke all on "app_private"."asset_depreciations" from public, anon, authenticated;
grant select on "app_private"."asset_depreciations" to authenticated;
grant all on "app_private"."asset_depreciations" to service_role;
drop policy if exists asset_depreciations_read on "app_private"."asset_depreciations";
create policy asset_depreciations_read on "app_private"."asset_depreciations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));



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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
end;
$$;
revoke execute on function "app_private"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) from public, anon;
grant execute on function "app_private"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, locationId, tag, serialNumber,
-- status, latitude, longitude and metadata, and the book value keys
-- acquisitionCost, currency, acquiredOn, usefulLifeMonths, residualValue,
-- depreciationMethod and depreciationRateBps. Retiring an asset releases it.
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
  if v_row."disposed_on" is not null and (
    update_asset.patch ?| array['acquisitionCost', 'currency', 'acquiredOn', 'usefulLifeMonths', 'residualValue', 'depreciationMethod', 'depreciationRateBps'] or coalesce(update_asset.patch ->> 'status', 'retired') <> 'retired'
  ) then
    raise exception 'a disposed asset stays retired and its book value can''t change' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if update_asset.patch ? 'currency' and not update_asset.patch ? 'acquisitionCost' and v_row."acquisition_cost" is not null
    and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency" then
    raise exception 'the amounts are in another currency than the asset''s cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if (
    (update_asset.patch ? 'acquisitionCost' and (update_asset.patch ->> 'acquisitionCost')::bigint is distinct from v_row."acquisition_cost")
    or (update_asset.patch ? 'currency' and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency")
    or (update_asset.patch ? 'acquiredOn' and (update_asset.patch ->> 'acquiredOn')::date is distinct from v_row."acquired_on")
  ) and exists (
    select 1 from "app_private"."asset_depreciations" y where y."asset_id" = v_row."id"
  ) then
    raise exception 'the cost, currency and acquisition date are fixed once the asset has depreciated' using errcode = '55000', hint = 'ASSETS_DEPRECIATION_STARTED';
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
    "acquisition_cost" = case when update_asset.patch ? 'acquisitionCost' then (update_asset.patch ->> 'acquisitionCost')::bigint else x."acquisition_cost" end,
    "currency" = case when update_asset.patch ? 'currency' then upper(update_asset.patch ->> 'currency') else x."currency" end,
    "acquired_on" = case when update_asset.patch ? 'acquiredOn' then (update_asset.patch ->> 'acquiredOn')::date else x."acquired_on" end,
    "useful_life_months" = case when update_asset.patch ? 'usefulLifeMonths' then (update_asset.patch ->> 'usefulLifeMonths')::integer else x."useful_life_months" end,
    "residual_value" = case when update_asset.patch ? 'residualValue' then coalesce((update_asset.patch ->> 'residualValue')::bigint, 0) else x."residual_value" end,
    "depreciation_method" = case when update_asset.patch ? 'depreciationMethod' then coalesce(update_asset.patch ->> 'depreciationMethod', 'none') else x."depreciation_method" end,
    "depreciation_rate_bps" = case when update_asset.patch ? 'depreciationRateBps' then (update_asset.patch ->> 'depreciationRateBps')::integer else x."depreciation_rate_bps" end,
    "assignee_type" = case when v_status = 'retired' then null else x."assignee_type" end,
    "assignee_id" = case when v_status = 'retired' then null else x."assignee_id" end,
    "retired_at" = case when v_status = 'retired' then coalesce(x."retired_at", now()) else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."acquisition_cost" is not null and v_row."currency" is null then
    raise exception 'an acquisition cost needs a currency' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."residual_value" > coalesce(v_row."acquisition_cost", 0) and v_row."depreciation_method" <> 'none' then
    raise exception 'the residual value is more than the acquisition cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" <> 'none' and (v_row."acquisition_cost" is null or v_row."acquired_on" is null) then
    raise exception 'depreciation needs an acquisition cost and date' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'straight_line' and v_row."useful_life_months" is null then
    raise exception 'straight-line depreciation needs a useful life' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'declining_balance' and v_row."depreciation_rate_bps" is null then
    raise exception 'declining-balance depreciation needs a rate' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."status" = 'retired' then
    raise exception 'a retired asset can''t be assigned' using errcode = '55000', hint = 'ASSETS_RETIRED';
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_-]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text) || (select jsonb_build_object('accumulatedDepreciation', q.total::text, 'bookValue', case when v_row."acquisition_cost" is null then null else (v_row."acquisition_cost" - q.total)::text end) from (select coalesce(sum(y."amount"), 0) as total from "app_private"."asset_depreciations" y where y."asset_id" = v_row."id") q) || jsonb_build_object(
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
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, x."created_at" as created_at, x."id" as id
    from "app_private"."assets" x
    where (list_assets.tenant is null or x."tenant_id" = list_assets.tenant)
      and (list_assets.location_id is null or x."location_id" in (select below.id from below))
      and (list_assets.kind is null or x."kind" = list_assets.kind)
      and (list_assets.status is null or x."status" = list_assets.status)
      and (list_assets.assignee_type is null or x."assignee_type" = list_assets.assignee_type)
      and (list_assets.assignee_id is null or x."assignee_id" = list_assets.assignee_id)
      and (list_assets.query is null or x."name" ilike '%' || list_assets.query || '%' or x."tag" = list_assets.query or x."serial_number" = list_assets.query)
      and (list_assets.before is null or x."created_at" < list_assets.before)
      and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)) or (x."assignee_type" = 'member' and coalesce(x."assignee_id" = auth.uid()::text, false)))
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
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
  raise exception 'install bookings or tasks to link assets' using errcode = '22023', hint = 'ASSETS_LINK_UNSUPPORTED';
end;
$$;
revoke execute on function "app_private"."set_asset_link"(text, uuid, uuid) from public, anon;
grant execute on function "app_private"."set_asset_link"(text, uuid, uuid) to authenticated, service_role;


-- Books an asset's depreciation for every month that ended on or before
-- until, from the month it was acquired in and stopping at the month it was
-- disposed of in. Straight line spreads the cost less the residual value over
-- the useful life; declining balance takes the yearly rate of the book value,
-- and writes the rest down at the end of the useful life when there is one.
-- A month books what the method has reached less what is booked, so a changed
-- life or residual value catches up in the next month. Returns the months
-- booked.
create or replace function "app_private"."asset_depreciate"(asset_id uuid, until date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_asset "app_private"."assets"%rowtype;
  v_row "app_private"."asset_depreciations"%rowtype;
  v_start date;
  v_month date;
  v_last date;
  v_booked bigint;
  v_base bigint;
  v_age integer;
  v_amount bigint;
  v_count integer := 0;
begin
  select * into v_asset from "app_private"."assets" x where x."id" = asset_depreciate.asset_id for update;
  if not found or v_asset."depreciation_method" = 'none'
    or v_asset."acquisition_cost" is null or v_asset."acquired_on" is null then
    return 0;
  end if;
  select max(y."period_start"), coalesce(sum(y."amount"), 0) into v_last, v_booked
  from "app_private"."asset_depreciations" y where y."asset_id" = v_asset."id";
  v_start := date_trunc('month', v_asset."acquired_on")::date;
  v_month := coalesce((v_last + interval '1 month')::date, v_start);
  v_base := v_asset."acquisition_cost" - v_asset."residual_value";
  while (v_month + interval '1 month' - interval '1 day')::date <= asset_depreciate.until
    and (v_asset."disposed_on" is null or v_month < date_trunc('month', v_asset."disposed_on")::date)
    and v_booked < v_base loop
    v_age := ((extract(year from v_month) - extract(year from v_start)) * 12 + extract(month from v_month) - extract(month from v_start))::integer + 1;
    if v_asset."depreciation_method" = 'straight_line' then
      v_amount := least(v_base, round(v_base::numeric * v_age / v_asset."useful_life_months")::bigint) - v_booked;
    elsif v_asset."useful_life_months" is not null and v_age >= v_asset."useful_life_months" then
      v_amount := v_base - v_booked;
    else
      v_amount := least(v_base - v_booked, round((v_asset."acquisition_cost" - v_booked)::numeric * v_asset."depreciation_rate_bps" / 120000)::bigint);
    end if;
    if v_amount > 0 then
      insert into "app_private"."asset_depreciations" ("tenant_id", "asset_id", "period_start", "amount")
      values (v_asset."tenant_id", v_asset."id", v_month, v_amount)
      returning * into v_row;
      null;
      v_booked := v_booked + v_amount;
      v_count := v_count + 1;
    end if;
    v_month := (v_month + interval '1 month')::date;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."asset_depreciate"(uuid, date) from public, anon, authenticated;

-- Books depreciation up to until (default today) for every asset in service
-- of an organization, or of every organization with tenant null. Run it
-- monthly from a scheduled job; it books each month once.
create or replace function "app_private"."run_asset_depreciation"(tenant uuid default null, until date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_until date := coalesce(run_asset_depreciation.until, current_date);
  v_id uuid;
  v_months integer;
  v_assets integer := 0;
  v_total integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role runs depreciation' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  for v_id in
    select x."id" from "app_private"."assets" x
    where (run_asset_depreciation.tenant is null or x."tenant_id" = run_asset_depreciation.tenant)
      and x."depreciation_method" <> 'none' and x."disposed_on" is null
    order by x."tenant_id", x."id"
  loop
    v_months := "app_private"."asset_depreciate"(v_id, v_until);
    if v_months > 0 then
      v_assets := v_assets + 1;
      v_total := v_total + v_months;
    end if;
  end loop;
  return jsonb_build_object('until', v_until, 'assets', v_assets, 'months', v_total);
end;
$$;
revoke execute on function "app_private"."run_asset_depreciation"(uuid, date) from public, anon, authenticated;
grant execute on function "app_private"."run_asset_depreciation"(uuid, date) to service_role;

-- Takes an asset off the books on disposed_on for amount, the proceeds in
-- currency (the asset's): books depreciation through the month before, then
-- retires and releases the asset and books the disposal, the proceeds less
-- the book value being a gain or a loss.
create or replace function "app_private"."dispose_asset"(asset_id uuid, disposed_on date, amount bigint default 0, currency text default null)
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
  select * into v_row from "app_private"."assets" x where x."id" = dispose_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."disposed_on" is not null then
    raise exception 'the asset is already disposed of' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if dispose_asset.disposed_on is null or coalesce(dispose_asset.amount, 0) < 0
    or dispose_asset.disposed_on < coalesce(v_row."acquired_on", dispose_asset.disposed_on) then
    raise exception 'a disposal needs a date on or after the acquisition and proceeds of 0 or more' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  if coalesce(dispose_asset.amount, 0) > 0 and (
    v_row."currency" is null or upper(coalesce(dispose_asset.currency, v_row."currency")) <> v_row."currency"
  ) then
    raise exception 'the proceeds need to be in the asset''s currency' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  perform "app_private"."asset_depreciate"(v_row."id", (date_trunc('month', dispose_asset.disposed_on) - interval '1 day')::date);
  update "app_private"."asset_assignments" y set "released_at" = now()
  where y."asset_id" = v_row."id" and y."released_at" is null;
  update "app_private"."assets" x set
    "disposed_on" = dispose_asset.disposed_on,
    "disposal_amount" = coalesce(dispose_asset.amount, 0),
    "status" = 'retired',
    "assignee_type" = null,
    "assignee_id" = null,
    "retired_at" = coalesce(x."retired_at", now()),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return "app_private"."get_asset"(v_row."id");
end;
$$;
revoke execute on function "app_private"."dispose_asset"(uuid, date, bigint, text) from public, anon;
grant execute on function "app_private"."dispose_asset"(uuid, date, bigint, text) to authenticated, service_role;

-- An asset's depreciation, oldest month first.
create or replace function "app_private"."list_asset_depreciations"(asset_id uuid, page_size integer default 600)
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
  select * into v_row from "app_private"."assets" x where x."id" = list_asset_depreciations.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'assetId', q."asset_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', v_row."currency", 'entryId', q."entry_id", 'createdAt', q."created_at") order by q."period_start"), '[]'::jsonb)
    from (
      select * from "app_private"."asset_depreciations" y where y."asset_id" = v_row."id"
      order by y."period_start"
      limit greatest(1, least(coalesce(list_asset_depreciations.page_size, 600), 1200))
    ) q
  );
end;
$$;
revoke execute on function "app_private"."list_asset_depreciations"(uuid, integer) from public, anon;
grant execute on function "app_private"."list_asset_depreciations"(uuid, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."asset_locations";
drop policy if exists bsb_tenant_scope_select on "app_private"."asset_locations";
create policy bsb_tenant_scope_select on "app_private"."asset_locations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."asset_locations";
create policy bsb_tenant_scope_insert on "app_private"."asset_locations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."asset_locations";
create policy bsb_tenant_scope_update on "app_private"."asset_locations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."asset_locations";
create policy bsb_tenant_scope_delete on "app_private"."asset_locations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."assets";
drop policy if exists bsb_tenant_scope_select on "app_private"."assets";
create policy bsb_tenant_scope_select on "app_private"."assets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."assets";
create policy bsb_tenant_scope_insert on "app_private"."assets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."assets";
create policy bsb_tenant_scope_update on "app_private"."assets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."assets";
create policy bsb_tenant_scope_delete on "app_private"."assets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."asset_assignments";
drop policy if exists bsb_tenant_scope_select on "app_private"."asset_assignments";
create policy bsb_tenant_scope_select on "app_private"."asset_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("asset_id" in (select y."id" from "app_private"."assets" y))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."asset_assignments";
create policy bsb_tenant_scope_insert on "app_private"."asset_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."asset_assignments";
create policy bsb_tenant_scope_update on "app_private"."asset_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."asset_assignments";
create policy bsb_tenant_scope_delete on "app_private"."asset_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."asset_depreciations";
drop policy if exists bsb_tenant_scope_select on "app_private"."asset_depreciations";
create policy bsb_tenant_scope_select on "app_private"."asset_depreciations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."asset_depreciations";
create policy bsb_tenant_scope_insert on "app_private"."asset_depreciations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."asset_depreciations";
create policy bsb_tenant_scope_update on "app_private"."asset_depreciations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."asset_depreciations";
create policy bsb_tenant_scope_delete on "app_private"."asset_depreciations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_114_assets.sql
-- better-supabase module: assets
-- @bsb-block-data assets
-- @bsb-hash sha256:cdfee733cdb1ab16291963d28940f13d8d33a1ba53dbbfb6af72eed615bd1cdf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_114_assets.sql
-- better-supabase module: assets
-- @bsb-block assets@1 managed
-- @bsb-hash sha256:13fb003aca6683636caa181a4bc63dbbaa939c0863f49a8afe3e60ae16e79f1b
-- A location hierarchy (site, building, unit) and an asset registry with tags, status, coordinates and assignment to members or records. Optional PostGIS stores points and areas as geography; bookings resources and work items can name an asset.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_locations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_depreciations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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
create index if not exists "asset_locations_parent_idx" on "better_supabase"."asset_locations" ("parent_id", "tenant_id");
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
  "assignee_type" text check ("assignee_type" is null or "assignee_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
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
create index if not exists "assets_location_idx" on "better_supabase"."assets" ("location_id", "tenant_id");
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
revoke all on "better_supabase"."asset_locations" from public, anon, authenticated;
grant select on "better_supabase"."asset_locations" to authenticated;
grant all on "better_supabase"."asset_locations" to service_role;
drop policy if exists asset_locations_read on "better_supabase"."asset_locations";
create policy asset_locations_read on "better_supabase"."asset_locations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));
alter table "better_supabase"."assets" enable row level security;
revoke all on "better_supabase"."assets" from public, anon, authenticated;
grant select on "better_supabase"."assets" to authenticated;
grant all on "better_supabase"."assets" to service_role;
drop policy if exists assets_read on "better_supabase"."assets";
create policy assets_read on "better_supabase"."assets"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text));
alter table "better_supabase"."asset_assignments" enable row level security;
revoke all on "better_supabase"."asset_assignments" from public, anon, authenticated;
grant select on "better_supabase"."asset_assignments" to authenticated;
grant all on "better_supabase"."asset_assignments" to service_role;
drop policy if exists asset_assignments_read on "better_supabase"."asset_assignments";
create policy asset_assignments_read on "better_supabase"."asset_assignments"
  for select to authenticated
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
drop trigger if exists "bsb_asset_locations_parent" on "better_supabase"."asset_locations";
create trigger "bsb_asset_locations_parent" before insert or update of "parent_id" on "better_supabase"."asset_locations"
  for each row execute function "better_supabase"."asset_location_check_parent"();

-- What an asset cost and how it depreciates, in bigint minor units of currency.
alter table "better_supabase"."assets" add column if not exists "acquisition_cost" bigint check ("acquisition_cost" >= 0);
alter table "better_supabase"."assets" add column if not exists "currency" text check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."assets" add column if not exists "acquired_on" date;
alter table "better_supabase"."assets" add column if not exists "useful_life_months" integer check ("useful_life_months" between 1 and 1200);
alter table "better_supabase"."assets" add column if not exists "residual_value" bigint not null default 0 check ("residual_value" >= 0);
alter table "better_supabase"."assets" add column if not exists "depreciation_method" text not null default 'none' check ("depreciation_method" in ('none', 'straight_line', 'declining_balance'));
-- Declining balance: the yearly rate in basis points of the book value.
alter table "better_supabase"."assets" add column if not exists "depreciation_rate_bps" integer check ("depreciation_rate_bps" between 1 and 100000);
alter table "better_supabase"."assets" add column if not exists "disposed_on" date;
alter table "better_supabase"."assets" add column if not exists "disposal_amount" bigint check ("disposal_amount" >= 0);

-- One month of an asset's depreciation; entry_id is its accounting entry.
create table if not exists "better_supabase"."asset_depreciations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "asset_id" uuid not null references "better_supabase"."assets" ("id") on delete cascade,
  "period_start" date not null check (extract(day from "period_start") = 1),
  "amount" bigint not null check ("amount" > 0),
  "entry_id" uuid,
  "created_at" timestamptz not null default now(),
  unique ("asset_id", "period_start")
);
create index if not exists "asset_depreciations_tenant_idx" on "better_supabase"."asset_depreciations" ("tenant_id", "period_start");
alter table "better_supabase"."asset_depreciations" enable row level security;
revoke all on "better_supabase"."asset_depreciations" from public, anon, authenticated;
grant select on "better_supabase"."asset_depreciations" to authenticated;
grant all on "better_supabase"."asset_depreciations" to service_role;
drop policy if exists asset_depreciations_read on "better_supabase"."asset_depreciations";
create policy asset_depreciations_read on "better_supabase"."asset_depreciations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));



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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
end;
$$;
revoke execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) from public, anon;
grant execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, locationId, tag, serialNumber,
-- status, latitude, longitude and metadata, and the book value keys
-- acquisitionCost, currency, acquiredOn, usefulLifeMonths, residualValue,
-- depreciationMethod and depreciationRateBps. Retiring an asset releases it.
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
  if v_row."disposed_on" is not null and (
    update_asset.patch ?| array['acquisitionCost', 'currency', 'acquiredOn', 'usefulLifeMonths', 'residualValue', 'depreciationMethod', 'depreciationRateBps'] or coalesce(update_asset.patch ->> 'status', 'retired') <> 'retired'
  ) then
    raise exception 'a disposed asset stays retired and its book value can''t change' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if update_asset.patch ? 'currency' and not update_asset.patch ? 'acquisitionCost' and v_row."acquisition_cost" is not null
    and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency" then
    raise exception 'the amounts are in another currency than the asset''s cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if (
    (update_asset.patch ? 'acquisitionCost' and (update_asset.patch ->> 'acquisitionCost')::bigint is distinct from v_row."acquisition_cost")
    or (update_asset.patch ? 'currency' and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency")
    or (update_asset.patch ? 'acquiredOn' and (update_asset.patch ->> 'acquiredOn')::date is distinct from v_row."acquired_on")
  ) and exists (
    select 1 from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
  ) then
    raise exception 'the cost, currency and acquisition date are fixed once the asset has depreciated' using errcode = '55000', hint = 'ASSETS_DEPRECIATION_STARTED';
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
    "acquisition_cost" = case when update_asset.patch ? 'acquisitionCost' then (update_asset.patch ->> 'acquisitionCost')::bigint else x."acquisition_cost" end,
    "currency" = case when update_asset.patch ? 'currency' then upper(update_asset.patch ->> 'currency') else x."currency" end,
    "acquired_on" = case when update_asset.patch ? 'acquiredOn' then (update_asset.patch ->> 'acquiredOn')::date else x."acquired_on" end,
    "useful_life_months" = case when update_asset.patch ? 'usefulLifeMonths' then (update_asset.patch ->> 'usefulLifeMonths')::integer else x."useful_life_months" end,
    "residual_value" = case when update_asset.patch ? 'residualValue' then coalesce((update_asset.patch ->> 'residualValue')::bigint, 0) else x."residual_value" end,
    "depreciation_method" = case when update_asset.patch ? 'depreciationMethod' then coalesce(update_asset.patch ->> 'depreciationMethod', 'none') else x."depreciation_method" end,
    "depreciation_rate_bps" = case when update_asset.patch ? 'depreciationRateBps' then (update_asset.patch ->> 'depreciationRateBps')::integer else x."depreciation_rate_bps" end,
    "assignee_type" = case when v_status = 'retired' then null else x."assignee_type" end,
    "assignee_id" = case when v_status = 'retired' then null else x."assignee_id" end,
    "retired_at" = case when v_status = 'retired' then coalesce(x."retired_at", now()) else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."acquisition_cost" is not null and v_row."currency" is null then
    raise exception 'an acquisition cost needs a currency' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."residual_value" > coalesce(v_row."acquisition_cost", 0) and v_row."depreciation_method" <> 'none' then
    raise exception 'the residual value is more than the acquisition cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" <> 'none' and (v_row."acquisition_cost" is null or v_row."acquired_on" is null) then
    raise exception 'depreciation needs an acquisition cost and date' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'straight_line' and v_row."useful_life_months" is null then
    raise exception 'straight-line depreciation needs a useful life' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'declining_balance' and v_row."depreciation_rate_bps" is null then
    raise exception 'declining-balance depreciation needs a rate' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."status" = 'retired' then
    raise exception 'a retired asset can''t be assigned' using errcode = '55000', hint = 'ASSETS_RETIRED';
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_-]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text) || (select jsonb_build_object('accumulatedDepreciation', q.total::text, 'bookValue', case when v_row."acquisition_cost" is null then null else (v_row."acquisition_cost" - q.total)::text end) from (select coalesce(sum(y."amount"), 0) as total from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id") q) || jsonb_build_object(
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
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, x."created_at" as created_at, x."id" as id
    from "better_supabase"."assets" x
    where (list_assets.tenant is null or x."tenant_id" = list_assets.tenant)
      and (list_assets.location_id is null or x."location_id" in (select below.id from below))
      and (list_assets.kind is null or x."kind" = list_assets.kind)
      and (list_assets.status is null or x."status" = list_assets.status)
      and (list_assets.assignee_type is null or x."assignee_type" = list_assets.assignee_type)
      and (list_assets.assignee_id is null or x."assignee_id" = list_assets.assignee_id)
      and (list_assets.query is null or x."name" ilike '%' || list_assets.query || '%' or x."tag" = list_assets.query or x."serial_number" = list_assets.query)
      and (list_assets.before is null or x."created_at" < list_assets.before)
      and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)) or (x."assignee_type" = 'member' and coalesce(x."assignee_id" = auth.uid()::text, false)))
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
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
  raise exception 'install bookings or tasks to link assets' using errcode = '22023', hint = 'ASSETS_LINK_UNSUPPORTED';
end;
$$;
revoke execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) to authenticated, service_role;


-- Books an asset's depreciation for every month that ended on or before
-- until, from the month it was acquired in and stopping at the month it was
-- disposed of in. Straight line spreads the cost less the residual value over
-- the useful life; declining balance takes the yearly rate of the book value,
-- and writes the rest down at the end of the useful life when there is one.
-- A month books what the method has reached less what is booked, so a changed
-- life or residual value catches up in the next month. Returns the months
-- booked.
create or replace function "better_supabase"."asset_depreciate"(asset_id uuid, until date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_asset "better_supabase"."assets"%rowtype;
  v_row "better_supabase"."asset_depreciations"%rowtype;
  v_start date;
  v_month date;
  v_last date;
  v_booked bigint;
  v_base bigint;
  v_age integer;
  v_amount bigint;
  v_count integer := 0;
begin
  select * into v_asset from "better_supabase"."assets" x where x."id" = asset_depreciate.asset_id for update;
  if not found or v_asset."depreciation_method" = 'none'
    or v_asset."acquisition_cost" is null or v_asset."acquired_on" is null then
    return 0;
  end if;
  select max(y."period_start"), coalesce(sum(y."amount"), 0) into v_last, v_booked
  from "better_supabase"."asset_depreciations" y where y."asset_id" = v_asset."id";
  v_start := date_trunc('month', v_asset."acquired_on")::date;
  v_month := coalesce((v_last + interval '1 month')::date, v_start);
  v_base := v_asset."acquisition_cost" - v_asset."residual_value";
  while (v_month + interval '1 month' - interval '1 day')::date <= asset_depreciate.until
    and (v_asset."disposed_on" is null or v_month < date_trunc('month', v_asset."disposed_on")::date)
    and v_booked < v_base loop
    v_age := ((extract(year from v_month) - extract(year from v_start)) * 12 + extract(month from v_month) - extract(month from v_start))::integer + 1;
    if v_asset."depreciation_method" = 'straight_line' then
      v_amount := least(v_base, round(v_base::numeric * v_age / v_asset."useful_life_months")::bigint) - v_booked;
    elsif v_asset."useful_life_months" is not null and v_age >= v_asset."useful_life_months" then
      v_amount := v_base - v_booked;
    else
      v_amount := least(v_base - v_booked, round((v_asset."acquisition_cost" - v_booked)::numeric * v_asset."depreciation_rate_bps" / 120000)::bigint);
    end if;
    if v_amount > 0 then
      insert into "better_supabase"."asset_depreciations" ("tenant_id", "asset_id", "period_start", "amount")
      values (v_asset."tenant_id", v_asset."id", v_month, v_amount)
      returning * into v_row;
      null;
      v_booked := v_booked + v_amount;
      v_count := v_count + 1;
    end if;
    v_month := (v_month + interval '1 month')::date;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."asset_depreciate"(uuid, date) from public, anon, authenticated;

-- Books depreciation up to until (default today) for every asset in service
-- of an organization, or of every organization with tenant null. Run it
-- monthly from a scheduled job; it books each month once.
create or replace function "better_supabase"."run_asset_depreciation"(tenant uuid default null, until date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_until date := coalesce(run_asset_depreciation.until, current_date);
  v_id uuid;
  v_months integer;
  v_assets integer := 0;
  v_total integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role runs depreciation' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  for v_id in
    select x."id" from "better_supabase"."assets" x
    where (run_asset_depreciation.tenant is null or x."tenant_id" = run_asset_depreciation.tenant)
      and x."depreciation_method" <> 'none' and x."disposed_on" is null
    order by x."tenant_id", x."id"
  loop
    v_months := "better_supabase"."asset_depreciate"(v_id, v_until);
    if v_months > 0 then
      v_assets := v_assets + 1;
      v_total := v_total + v_months;
    end if;
  end loop;
  return jsonb_build_object('until', v_until, 'assets', v_assets, 'months', v_total);
end;
$$;
revoke execute on function "better_supabase"."run_asset_depreciation"(uuid, date) from public, anon, authenticated;
grant execute on function "better_supabase"."run_asset_depreciation"(uuid, date) to service_role;

-- Takes an asset off the books on disposed_on for amount, the proceeds in
-- currency (the asset's): books depreciation through the month before, then
-- retires and releases the asset and books the disposal, the proceeds less
-- the book value being a gain or a loss.
create or replace function "better_supabase"."dispose_asset"(asset_id uuid, disposed_on date, amount bigint default 0, currency text default null)
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
  select * into v_row from "better_supabase"."assets" x where x."id" = dispose_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."disposed_on" is not null then
    raise exception 'the asset is already disposed of' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if dispose_asset.disposed_on is null or coalesce(dispose_asset.amount, 0) < 0
    or dispose_asset.disposed_on < coalesce(v_row."acquired_on", dispose_asset.disposed_on) then
    raise exception 'a disposal needs a date on or after the acquisition and proceeds of 0 or more' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  if coalesce(dispose_asset.amount, 0) > 0 and (
    v_row."currency" is null or upper(coalesce(dispose_asset.currency, v_row."currency")) <> v_row."currency"
  ) then
    raise exception 'the proceeds need to be in the asset''s currency' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  perform "better_supabase"."asset_depreciate"(v_row."id", (date_trunc('month', dispose_asset.disposed_on) - interval '1 day')::date);
  update "better_supabase"."asset_assignments" y set "released_at" = now()
  where y."asset_id" = v_row."id" and y."released_at" is null;
  update "better_supabase"."assets" x set
    "disposed_on" = dispose_asset.disposed_on,
    "disposal_amount" = coalesce(dispose_asset.amount, 0),
    "status" = 'retired',
    "assignee_type" = null,
    "assignee_id" = null,
    "retired_at" = coalesce(x."retired_at", now()),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return "better_supabase"."get_asset"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."dispose_asset"(uuid, date, bigint, text) from public, anon;
grant execute on function "better_supabase"."dispose_asset"(uuid, date, bigint, text) to authenticated, service_role;

-- An asset's depreciation, oldest month first.
create or replace function "better_supabase"."list_asset_depreciations"(asset_id uuid, page_size integer default 600)
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
  select * into v_row from "better_supabase"."assets" x where x."id" = list_asset_depreciations.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'assetId', q."asset_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', v_row."currency", 'entryId', q."entry_id", 'createdAt', q."created_at") order by q."period_start"), '[]'::jsonb)
    from (
      select * from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
      order by y."period_start"
      limit greatest(1, least(coalesce(list_asset_depreciations.page_size, 600), 1200))
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_asset_depreciations"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_asset_depreciations"(uuid, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_locations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_select on "better_supabase"."asset_locations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_locations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_update on "better_supabase"."asset_locations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_locations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."assets";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."assets";
create policy bsb_tenant_scope_select on "better_supabase"."assets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assets";
create policy bsb_tenant_scope_insert on "better_supabase"."assets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."assets";
create policy bsb_tenant_scope_update on "better_supabase"."assets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assets";
create policy bsb_tenant_scope_delete on "better_supabase"."assets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."asset_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("asset_id" in (select y."id" from "better_supabase"."assets" y))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."asset_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_depreciations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_select on "better_supabase"."asset_depreciations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_depreciations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_update on "better_supabase"."asset_depreciations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_depreciations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

create or replace function "api"."run_asset_depreciation"(tenant uuid default null, until date default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."run_asset_depreciation"($1, $2) $$;
revoke execute on function "api"."run_asset_depreciation"(uuid, date) from public, anon, authenticated;
grant execute on function "api"."run_asset_depreciation"(uuid, date) to service_role;

create or replace function "api"."dispose_asset"(asset_id uuid, disposed_on date, amount bigint default 0, currency text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."dispose_asset"($1, $2, $3, $4) $$;
revoke execute on function "api"."dispose_asset"(uuid, date, bigint, text) from public, anon;
grant execute on function "api"."dispose_asset"(uuid, date, bigint, text) to authenticated, service_role;

create or replace function "api"."list_asset_depreciations"(asset_id uuid, page_size integer default 600)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_asset_depreciations"($1, $2) $$;
revoke execute on function "api"."list_asset_depreciations"(uuid, integer) from public, anon;
grant execute on function "api"."list_asset_depreciations"(uuid, integer) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_114_assets.sql
-- better-supabase module: assets
-- @bsb-block-data assets
-- @bsb-hash sha256:cdfee733cdb1ab16291963d28940f13d8d33a1ba53dbbfb6af72eed615bd1cdf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_114_assets.sql
-- better-supabase module: assets
-- @bsb-block assets@1 managed
-- @bsb-hash sha256:2d9b66fefbd29e4b4bf43e8c5e45052e1cda3f916dd2a54df4bdbbeff4803336
-- A location hierarchy (site, building, unit) and an asset registry with tags, status, coordinates and assignment to members or records. Optional PostGIS stores points and areas as geography; bookings resources and work items can name an asset.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_locations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_depreciations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- better_supabase.asset_locations is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."asset_locations" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."asset_locations" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."asset_locations" add column if not exists "parent_id" uuid references "better_supabase"."asset_locations" ("id") on delete restrict;
alter table "better_supabase"."asset_locations" add column if not exists "kind" text check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$');
alter table "better_supabase"."asset_locations" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."asset_locations" add column if not exists "code" text check ("code" is null or length("code") between 1 and 100);
alter table "better_supabase"."asset_locations" add column if not exists "address" jsonb not null default '{}'::jsonb check (jsonb_typeof("address") = 'object');
alter table "better_supabase"."asset_locations" add column if not exists "latitude" double precision check ("latitude" between -90 and 90);
alter table "better_supabase"."asset_locations" add column if not exists "longitude" double precision check ("longitude" between -180 and 180);
alter table "better_supabase"."asset_locations" add column if not exists "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object');
alter table "better_supabase"."asset_locations" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."asset_locations" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."asset_locations" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "asset_locations_parent_idx" on "better_supabase"."asset_locations" ("parent_id", "tenant_id");
create index if not exists "asset_locations_coordinates_idx" on "better_supabase"."asset_locations" ("tenant_id", "latitude", "longitude") where "latitude" is not null;

-- better_supabase.assets is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."assets" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."assets" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."assets" add column if not exists "location_id" uuid references "better_supabase"."asset_locations" ("id") on delete set null;
alter table "better_supabase"."assets" add column if not exists "kind" text check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$');
alter table "better_supabase"."assets" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."assets" add column if not exists "tag" text check ("tag" is null or length("tag") between 1 and 100);
alter table "better_supabase"."assets" add column if not exists "serial_number" text check ("serial_number" is null or length("serial_number") <= 200);
alter table "better_supabase"."assets" add column if not exists "status" text not null default 'active' check ("status" in ('active', 'maintenance', 'retired'));
alter table "better_supabase"."assets" add column if not exists "assignee_type" text check ("assignee_type" is null or "assignee_type" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."assets" add column if not exists "assignee_id" text;
alter table "better_supabase"."assets" add column if not exists "latitude" double precision check ("latitude" between -90 and 90);
alter table "better_supabase"."assets" add column if not exists "longitude" double precision check ("longitude" between -180 and 180);
alter table "better_supabase"."assets" add column if not exists "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object');
alter table "better_supabase"."assets" add column if not exists "retired_at" timestamptz;
alter table "better_supabase"."assets" add column if not exists "created_by" uuid;
alter table "better_supabase"."assets" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."assets" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists "assets_location_idx" on "better_supabase"."assets" ("location_id", "tenant_id");
create index if not exists "assets_assignee_idx" on "better_supabase"."assets" ("tenant_id", "assignee_type", "assignee_id") where "assignee_type" is not null;
create index if not exists "assets_kind_idx" on "better_supabase"."assets" ("tenant_id", "kind", "status");
create index if not exists "assets_coordinates_idx" on "better_supabase"."assets" ("tenant_id", "latitude", "longitude") where "latitude" is not null;

-- better_supabase.asset_assignments is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."asset_assignments" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."asset_assignments" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."asset_assignments" add column if not exists "asset_id" uuid references "better_supabase"."assets" ("id") on delete cascade;
alter table "better_supabase"."asset_assignments" add column if not exists "assignee_type" text;
alter table "better_supabase"."asset_assignments" add column if not exists "assignee_id" text;
alter table "better_supabase"."asset_assignments" add column if not exists "note" text check ("note" is null or length("note") <= 2000);
alter table "better_supabase"."asset_assignments" add column if not exists "assigned_by" uuid;
alter table "better_supabase"."asset_assignments" add column if not exists "assigned_at" timestamptz not null default now();
alter table "better_supabase"."asset_assignments" add column if not exists "released_at" timestamptz;
create unique index if not exists "asset_assignments_open_idx" on "better_supabase"."asset_assignments" ("asset_id") where "released_at" is null;
create index if not exists "asset_assignments_history_idx" on "better_supabase"."asset_assignments" ("asset_id", "assigned_at" desc);

alter table "better_supabase"."asset_locations" enable row level security;
grant select on "better_supabase"."asset_locations" to authenticated;
grant all on "better_supabase"."asset_locations" to service_role;
drop policy if exists bsb_asset_locations_select on "better_supabase"."asset_locations";
create policy bsb_asset_locations_select on "better_supabase"."asset_locations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));
alter table "better_supabase"."assets" enable row level security;
grant select on "better_supabase"."assets" to authenticated;
grant all on "better_supabase"."assets" to service_role;
drop policy if exists bsb_assets_select on "better_supabase"."assets";
create policy bsb_assets_select on "better_supabase"."assets"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text));
alter table "better_supabase"."asset_assignments" enable row level security;
grant select on "better_supabase"."asset_assignments" to authenticated;
grant all on "better_supabase"."asset_assignments" to service_role;
drop policy if exists bsb_asset_assignments_select on "better_supabase"."asset_assignments";
create policy bsb_asset_assignments_select on "better_supabase"."asset_assignments"
  for select to authenticated
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
drop trigger if exists "bsb_asset_locations_parent" on "better_supabase"."asset_locations";
create trigger "bsb_asset_locations_parent" before insert or update of "parent_id" on "better_supabase"."asset_locations"
  for each row execute function "better_supabase"."asset_location_check_parent"();

-- What an asset cost and how it depreciates, in bigint minor units of currency.
alter table "better_supabase"."assets" add column if not exists "acquisition_cost" bigint check ("acquisition_cost" >= 0);
alter table "better_supabase"."assets" add column if not exists "currency" text check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."assets" add column if not exists "acquired_on" date;
alter table "better_supabase"."assets" add column if not exists "useful_life_months" integer check ("useful_life_months" between 1 and 1200);
alter table "better_supabase"."assets" add column if not exists "residual_value" bigint not null default 0 check ("residual_value" >= 0);
alter table "better_supabase"."assets" add column if not exists "depreciation_method" text not null default 'none' check ("depreciation_method" in ('none', 'straight_line', 'declining_balance'));
-- Declining balance: the yearly rate in basis points of the book value.
alter table "better_supabase"."assets" add column if not exists "depreciation_rate_bps" integer check ("depreciation_rate_bps" between 1 and 100000);
alter table "better_supabase"."assets" add column if not exists "disposed_on" date;
alter table "better_supabase"."assets" add column if not exists "disposal_amount" bigint check ("disposal_amount" >= 0);

-- One month of an asset's depreciation; entry_id is its accounting entry.
-- better_supabase.asset_depreciations is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."asset_depreciations" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."asset_depreciations" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."asset_depreciations" add column if not exists "asset_id" uuid references "better_supabase"."assets" ("id") on delete cascade;
alter table "better_supabase"."asset_depreciations" add column if not exists "period_start" date check (extract(day from "period_start") = 1);
alter table "better_supabase"."asset_depreciations" add column if not exists "amount" bigint check ("amount" > 0);
alter table "better_supabase"."asset_depreciations" add column if not exists "entry_id" uuid;
alter table "better_supabase"."asset_depreciations" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "asset_depreciations_tenant_idx" on "better_supabase"."asset_depreciations" ("tenant_id", "period_start");
alter table "better_supabase"."asset_depreciations" enable row level security;
grant select on "better_supabase"."asset_depreciations" to authenticated;
grant all on "better_supabase"."asset_depreciations" to service_role;
drop policy if exists bsb_asset_depreciations_select on "better_supabase"."asset_depreciations";
create policy bsb_asset_depreciations_select on "better_supabase"."asset_depreciations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')));



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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
end;
$$;
revoke execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) from public, anon;
grant execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, locationId, tag, serialNumber,
-- status, latitude, longitude and metadata, and the book value keys
-- acquisitionCost, currency, acquiredOn, usefulLifeMonths, residualValue,
-- depreciationMethod and depreciationRateBps. Retiring an asset releases it.
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
  v_status := case when update_asset.patch ? 'status' then update_asset.patch ->> 'status' else v_row."status"::text end;
  if update_asset.patch ? 'tag' and update_asset.patch ->> 'tag' is not null and exists (
    select 1 from "better_supabase"."assets" x where x."tenant_id" = v_row."tenant_id" and x."tag" = update_asset.patch ->> 'tag' and x."id" <> v_row."id"
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  if v_status = 'retired' and v_row."status" <> 'retired' then
    update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  end if;
  if v_row."disposed_on" is not null and (
    update_asset.patch ?| array['acquisitionCost', 'currency', 'acquiredOn', 'usefulLifeMonths', 'residualValue', 'depreciationMethod', 'depreciationRateBps'] or coalesce(update_asset.patch ->> 'status', 'retired') <> 'retired'
  ) then
    raise exception 'a disposed asset stays retired and its book value can''t change' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if update_asset.patch ? 'currency' and not update_asset.patch ? 'acquisitionCost' and v_row."acquisition_cost" is not null
    and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency" then
    raise exception 'the amounts are in another currency than the asset''s cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if (
    (update_asset.patch ? 'acquisitionCost' and (update_asset.patch ->> 'acquisitionCost')::bigint is distinct from v_row."acquisition_cost")
    or (update_asset.patch ? 'currency' and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency")
    or (update_asset.patch ? 'acquiredOn' and (update_asset.patch ->> 'acquiredOn')::date is distinct from v_row."acquired_on")
  ) and exists (
    select 1 from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
  ) then
    raise exception 'the cost, currency and acquisition date are fixed once the asset has depreciated' using errcode = '55000', hint = 'ASSETS_DEPRECIATION_STARTED';
  end if;
  update "better_supabase"."assets" x set
    "kind" = case when update_asset.patch ? 'kind' then update_asset.patch ->> 'kind' else x."kind" end,
    "name" = case when update_asset.patch ? 'name' then trim(update_asset.patch ->> 'name') else x."name" end,
    "location_id" = v_location,
    "tag" = case when update_asset.patch ? 'tag' then update_asset.patch ->> 'tag' else x."tag" end,
    "serial_number" = case when update_asset.patch ? 'serialNumber' then update_asset.patch ->> 'serialNumber' else x."serial_number" end,
    "status" = better_supabase.as_column_type(v_status, (null::"better_supabase"."assets")."status"),
    "latitude" = case when update_asset.patch ? 'latitude' then (update_asset.patch ->> 'latitude')::double precision else x."latitude" end,
    "longitude" = case when update_asset.patch ? 'longitude' then (update_asset.patch ->> 'longitude')::double precision else x."longitude" end,
    "metadata" = case when update_asset.patch ? 'metadata' then coalesce(nullif(update_asset.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x."metadata" end,
    "acquisition_cost" = case when update_asset.patch ? 'acquisitionCost' then (update_asset.patch ->> 'acquisitionCost')::bigint else x."acquisition_cost" end,
    "currency" = case when update_asset.patch ? 'currency' then upper(update_asset.patch ->> 'currency') else x."currency" end,
    "acquired_on" = case when update_asset.patch ? 'acquiredOn' then (update_asset.patch ->> 'acquiredOn')::date else x."acquired_on" end,
    "useful_life_months" = case when update_asset.patch ? 'usefulLifeMonths' then (update_asset.patch ->> 'usefulLifeMonths')::integer else x."useful_life_months" end,
    "residual_value" = case when update_asset.patch ? 'residualValue' then coalesce((update_asset.patch ->> 'residualValue')::bigint, 0) else x."residual_value" end,
    "depreciation_method" = case when update_asset.patch ? 'depreciationMethod' then coalesce(update_asset.patch ->> 'depreciationMethod', 'none') else x."depreciation_method" end,
    "depreciation_rate_bps" = case when update_asset.patch ? 'depreciationRateBps' then (update_asset.patch ->> 'depreciationRateBps')::integer else x."depreciation_rate_bps" end,
    "assignee_type" = case when v_status = 'retired' then null else x."assignee_type" end,
    "assignee_id" = case when v_status = 'retired' then null else x."assignee_id" end,
    "retired_at" = case when v_status = 'retired' then coalesce(x."retired_at", now()) else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."acquisition_cost" is not null and v_row."currency" is null then
    raise exception 'an acquisition cost needs a currency' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."residual_value" > coalesce(v_row."acquisition_cost", 0) and v_row."depreciation_method" <> 'none' then
    raise exception 'the residual value is more than the acquisition cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" <> 'none' and (v_row."acquisition_cost" is null or v_row."acquired_on" is null) then
    raise exception 'depreciation needs an acquisition cost and date' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'straight_line' and v_row."useful_life_months" is null then
    raise exception 'straight-line depreciation needs a useful life' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'declining_balance' and v_row."depreciation_rate_bps" is null then
    raise exception 'declining-balance depreciation needs a rate' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."status" = 'retired' then
    raise exception 'a retired asset can''t be assigned' using errcode = '55000', hint = 'ASSETS_RETIRED';
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_-]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text) || (select jsonb_build_object('accumulatedDepreciation', q.total::text, 'bookValue', case when v_row."acquisition_cost" is null then null else (v_row."acquisition_cost" - q.total)::text end) from (select coalesce(sum(y."amount"), 0) as total from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id") q) || jsonb_build_object(
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
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, x."created_at" as created_at, x."id" as id
    from "better_supabase"."assets" x
    where (list_assets.tenant is null or x."tenant_id" = list_assets.tenant)
      and (list_assets.location_id is null or x."location_id" in (select below.id from below))
      and (list_assets.kind is null or x."kind" = list_assets.kind)
      and (list_assets.status is null or x."status"::text = list_assets.status)
      and (list_assets.assignee_type is null or x."assignee_type" = list_assets.assignee_type)
      and (list_assets.assignee_id is null or x."assignee_id" = list_assets.assignee_id)
      and (list_assets.query is null or x."name" ilike '%' || list_assets.query || '%' or x."tag" = list_assets.query or x."serial_number" = list_assets.query)
      and (list_assets.before is null or x."created_at" < list_assets.before)
      and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)) or (x."assignee_type" = 'member' and coalesce(x."assignee_id" = auth.uid()::text, false)))
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
        select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
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
  raise exception 'install bookings or tasks to link assets' using errcode = '22023', hint = 'ASSETS_LINK_UNSUPPORTED';
end;
$$;
revoke execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) to authenticated, service_role;


-- Books an asset's depreciation for every month that ended on or before
-- until, from the month it was acquired in and stopping at the month it was
-- disposed of in. Straight line spreads the cost less the residual value over
-- the useful life; declining balance takes the yearly rate of the book value,
-- and writes the rest down at the end of the useful life when there is one.
-- A month books what the method has reached less what is booked, so a changed
-- life or residual value catches up in the next month. Returns the months
-- booked.
create or replace function "better_supabase"."asset_depreciate"(asset_id uuid, until date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_asset "better_supabase"."assets"%rowtype;
  v_row "better_supabase"."asset_depreciations"%rowtype;
  v_start date;
  v_month date;
  v_last date;
  v_booked bigint;
  v_base bigint;
  v_age integer;
  v_amount bigint;
  v_count integer := 0;
begin
  select * into v_asset from "better_supabase"."assets" x where x."id" = asset_depreciate.asset_id for update;
  if not found or v_asset."depreciation_method" = 'none'
    or v_asset."acquisition_cost" is null or v_asset."acquired_on" is null then
    return 0;
  end if;
  select max(y."period_start"), coalesce(sum(y."amount"), 0) into v_last, v_booked
  from "better_supabase"."asset_depreciations" y where y."asset_id" = v_asset."id";
  v_start := date_trunc('month', v_asset."acquired_on")::date;
  v_month := coalesce((v_last + interval '1 month')::date, v_start);
  v_base := v_asset."acquisition_cost" - v_asset."residual_value";
  while (v_month + interval '1 month' - interval '1 day')::date <= asset_depreciate.until
    and (v_asset."disposed_on" is null or v_month < date_trunc('month', v_asset."disposed_on")::date)
    and v_booked < v_base loop
    v_age := ((extract(year from v_month) - extract(year from v_start)) * 12 + extract(month from v_month) - extract(month from v_start))::integer + 1;
    if v_asset."depreciation_method" = 'straight_line' then
      v_amount := least(v_base, round(v_base::numeric * v_age / v_asset."useful_life_months")::bigint) - v_booked;
    elsif v_asset."useful_life_months" is not null and v_age >= v_asset."useful_life_months" then
      v_amount := v_base - v_booked;
    else
      v_amount := least(v_base - v_booked, round((v_asset."acquisition_cost" - v_booked)::numeric * v_asset."depreciation_rate_bps" / 120000)::bigint);
    end if;
    if v_amount > 0 then
      insert into "better_supabase"."asset_depreciations" ("tenant_id", "asset_id", "period_start", "amount")
      values (v_asset."tenant_id", v_asset."id", v_month, v_amount)
      returning * into v_row;
      null;
      v_booked := v_booked + v_amount;
      v_count := v_count + 1;
    end if;
    v_month := (v_month + interval '1 month')::date;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."asset_depreciate"(uuid, date) from public, anon, authenticated;

-- Books depreciation up to until (default today) for every asset in service
-- of an organization, or of every organization with tenant null. Run it
-- monthly from a scheduled job; it books each month once.
create or replace function "better_supabase"."run_asset_depreciation"(tenant uuid default null, until date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_until date := coalesce(run_asset_depreciation.until, current_date);
  v_id uuid;
  v_months integer;
  v_assets integer := 0;
  v_total integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role runs depreciation' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  for v_id in
    select x."id" from "better_supabase"."assets" x
    where (run_asset_depreciation.tenant is null or x."tenant_id" = run_asset_depreciation.tenant)
      and x."depreciation_method" <> 'none' and x."disposed_on" is null
    order by x."tenant_id", x."id"
  loop
    v_months := "better_supabase"."asset_depreciate"(v_id, v_until);
    if v_months > 0 then
      v_assets := v_assets + 1;
      v_total := v_total + v_months;
    end if;
  end loop;
  return jsonb_build_object('until', v_until, 'assets', v_assets, 'months', v_total);
end;
$$;
revoke execute on function "better_supabase"."run_asset_depreciation"(uuid, date) from public, anon, authenticated;
grant execute on function "better_supabase"."run_asset_depreciation"(uuid, date) to service_role;

-- Takes an asset off the books on disposed_on for amount, the proceeds in
-- currency (the asset's): books depreciation through the month before, then
-- retires and releases the asset and books the disposal, the proceeds less
-- the book value being a gain or a loss.
create or replace function "better_supabase"."dispose_asset"(asset_id uuid, disposed_on date, amount bigint default 0, currency text default null)
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
  select * into v_row from "better_supabase"."assets" x where x."id" = dispose_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."disposed_on" is not null then
    raise exception 'the asset is already disposed of' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if dispose_asset.disposed_on is null or coalesce(dispose_asset.amount, 0) < 0
    or dispose_asset.disposed_on < coalesce(v_row."acquired_on", dispose_asset.disposed_on) then
    raise exception 'a disposal needs a date on or after the acquisition and proceeds of 0 or more' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  if coalesce(dispose_asset.amount, 0) > 0 and (
    v_row."currency" is null or upper(coalesce(dispose_asset.currency, v_row."currency")) <> v_row."currency"
  ) then
    raise exception 'the proceeds need to be in the asset''s currency' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  perform "better_supabase"."asset_depreciate"(v_row."id", (date_trunc('month', dispose_asset.disposed_on) - interval '1 day')::date);
  update "better_supabase"."asset_assignments" y set "released_at" = now()
  where y."asset_id" = v_row."id" and y."released_at" is null;
  update "better_supabase"."assets" x set
    "disposed_on" = dispose_asset.disposed_on,
    "disposal_amount" = coalesce(dispose_asset.amount, 0),
    "status" = better_supabase.as_column_type('retired', (null::"better_supabase"."assets")."status"),
    "assignee_type" = null,
    "assignee_id" = null,
    "retired_at" = coalesce(x."retired_at", now()),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return "better_supabase"."get_asset"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."dispose_asset"(uuid, date, bigint, text) from public, anon;
grant execute on function "better_supabase"."dispose_asset"(uuid, date, bigint, text) to authenticated, service_role;

-- An asset's depreciation, oldest month first.
create or replace function "better_supabase"."list_asset_depreciations"(asset_id uuid, page_size integer default 600)
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
  select * into v_row from "better_supabase"."assets" x where x."id" = list_asset_depreciations.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'assetId', q."asset_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', v_row."currency", 'entryId', q."entry_id", 'createdAt', q."created_at") order by q."period_start"), '[]'::jsonb)
    from (
      select * from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
      order by y."period_start"
      limit greatest(1, least(coalesce(list_asset_depreciations.page_size, 600), 1200))
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_asset_depreciations"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_asset_depreciations"(uuid, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_locations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_select on "better_supabase"."asset_locations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_locations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_update on "better_supabase"."asset_locations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_locations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."assets";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."assets";
create policy bsb_tenant_scope_select on "better_supabase"."assets" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assets";
create policy bsb_tenant_scope_insert on "better_supabase"."assets" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."assets";
create policy bsb_tenant_scope_update on "better_supabase"."assets" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assets";
create policy bsb_tenant_scope_delete on "better_supabase"."assets" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."asset_assignments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("asset_id" in (select y."id" from "better_supabase"."assets" y))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_assignments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."asset_assignments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_assignments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_depreciations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_select on "better_supabase"."asset_depreciations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('assets.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_depreciations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_update on "better_supabase"."asset_depreciations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_depreciations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_114_assets.sql
-- better-supabase module: assets
-- @bsb-block-data assets
-- @bsb-hash sha256:cdfee733cdb1ab16291963d28940f13d8d33a1ba53dbbfb6af72eed615bd1cdf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_114_assets.sql
-- better-supabase module: assets
-- @bsb-block assets@1 managed
-- @bsb-hash sha256:88cf7a428fca4c2d99e3a00ff6ac44bf8b00e1e6468fc4566aae302fdc71b1c8
-- A location hierarchy (site, building, unit) and an asset registry with tags, status, coordinates and assignment to members or records. Optional PostGIS stores points and areas as geography; bookings resources and work items can name an asset.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_locations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_locations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."assets";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assets";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_assignments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_assignments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_depreciations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_depreciations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."asset_locations" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
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
  unique ("org_id", "code"),
  check (("latitude" is null) = ("longitude" is null))
);
create index if not exists "asset_locations_parent_idx" on "better_supabase"."asset_locations" ("parent_id", "org_id");
create index if not exists "asset_locations_coordinates_idx" on "better_supabase"."asset_locations" ("org_id", "latitude", "longitude") where "latitude" is not null;

create table if not exists "better_supabase"."assets" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "location_id" uuid references "better_supabase"."asset_locations" ("id") on delete set null,
  "kind" text not null check ("kind" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  -- The asset tag, unique per organization.
  "tag" text check ("tag" is null or length("tag") between 1 and 100),
  "serial_number" text check ("serial_number" is null or length("serial_number") <= 200),
  "status" text not null default 'active' check ("status" in ('active', 'maintenance', 'retired')),
  -- member (a user id) or a subject type such as party, with its id.
  "assignee_type" text check ("assignee_type" is null or "assignee_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "assignee_id" text,
  -- Where a moving asset (a vehicle) was last seen.
  "latitude" double precision check ("latitude" between -90 and 90),
  "longitude" double precision check ("longitude" between -180 and 180),
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "retired_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("org_id", "tag"),
  check (("assignee_type" is null) = ("assignee_id" is null)),
  check (("latitude" is null) = ("longitude" is null))
);
create index if not exists "assets_location_idx" on "better_supabase"."assets" ("location_id", "org_id");
create index if not exists "assets_assignee_idx" on "better_supabase"."assets" ("org_id", "assignee_type", "assignee_id") where "assignee_type" is not null;
create index if not exists "assets_kind_idx" on "better_supabase"."assets" ("org_id", "kind", "status");
create index if not exists "assets_coordinates_idx" on "better_supabase"."assets" ("org_id", "latitude", "longitude") where "latitude" is not null;

create table if not exists "better_supabase"."asset_assignments" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
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
revoke all on "better_supabase"."asset_locations" from public, anon, authenticated;
grant select on "better_supabase"."asset_locations" to authenticated;
grant all on "better_supabase"."asset_locations" to service_role;
drop policy if exists asset_locations_read on "better_supabase"."asset_locations";
create policy asset_locations_read on "better_supabase"."asset_locations"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('assets.read')));
alter table "better_supabase"."assets" enable row level security;
revoke all on "better_supabase"."assets" from public, anon, authenticated;
grant select on "better_supabase"."assets" to authenticated;
grant all on "better_supabase"."assets" to service_role;
drop policy if exists assets_read on "better_supabase"."assets";
create policy assets_read on "better_supabase"."assets"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text));
alter table "better_supabase"."asset_assignments" enable row level security;
revoke all on "better_supabase"."asset_assignments" from public, anon, authenticated;
grant select on "better_supabase"."asset_assignments" to authenticated;
grant all on "better_supabase"."asset_assignments" to service_role;
drop policy if exists asset_assignments_read on "better_supabase"."asset_assignments";
create policy asset_assignments_read on "better_supabase"."asset_assignments"
  for select to authenticated
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
    select 1 from "better_supabase"."asset_locations" x where x."id" = new."parent_id" and x."org_id" = new."org_id"
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
drop trigger if exists "bsb_asset_locations_parent" on "better_supabase"."asset_locations";
create trigger "bsb_asset_locations_parent" before insert or update of "parent_id" on "better_supabase"."asset_locations"
  for each row execute function "better_supabase"."asset_location_check_parent"();

-- What an asset cost and how it depreciates, in bigint minor units of currency.
alter table "better_supabase"."assets" add column if not exists "acquisition_cost" bigint check ("acquisition_cost" >= 0);
alter table "better_supabase"."assets" add column if not exists "currency" text check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."assets" add column if not exists "acquired_on" date;
alter table "better_supabase"."assets" add column if not exists "useful_life_months" integer check ("useful_life_months" between 1 and 1200);
alter table "better_supabase"."assets" add column if not exists "residual_value" bigint not null default 0 check ("residual_value" >= 0);
alter table "better_supabase"."assets" add column if not exists "depreciation_method" text not null default 'none' check ("depreciation_method" in ('none', 'straight_line', 'declining_balance'));
-- Declining balance: the yearly rate in basis points of the book value.
alter table "better_supabase"."assets" add column if not exists "depreciation_rate_bps" integer check ("depreciation_rate_bps" between 1 and 100000);
alter table "better_supabase"."assets" add column if not exists "disposed_on" date;
alter table "better_supabase"."assets" add column if not exists "disposal_amount" bigint check ("disposal_amount" >= 0);

-- One month of an asset's depreciation; entry_id is its accounting entry.
create table if not exists "better_supabase"."asset_depreciations" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "asset_id" uuid not null references "better_supabase"."assets" ("id") on delete cascade,
  "period_start" date not null check (extract(day from "period_start") = 1),
  "amount" bigint not null check ("amount" > 0),
  "entry_id" uuid,
  "created_at" timestamptz not null default now(),
  unique ("asset_id", "period_start")
);
create index if not exists "asset_depreciations_tenant_idx" on "better_supabase"."asset_depreciations" ("org_id", "period_start");
alter table "better_supabase"."asset_depreciations" enable row level security;
revoke all on "better_supabase"."asset_depreciations" from public, anon, authenticated;
grant select on "better_supabase"."asset_depreciations" to authenticated;
grant all on "better_supabase"."asset_depreciations" to service_role;
drop policy if exists asset_depreciations_read on "better_supabase"."asset_depreciations";
create policy asset_depreciations_read on "better_supabase"."asset_depreciations"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('assets.read')));



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
    select 1 from "better_supabase"."asset_locations" x where x."org_id" = create_asset_location.tenant and x."code" = create_asset_location.code
  ) then
    raise exception 'a location with this code already exists' using errcode = '23505', hint = 'ASSETS_CODE_TAKEN';
  end if;
  insert into "better_supabase"."asset_locations" ("org_id", "parent_id", "kind", "name", "code", "address", "latitude", "longitude", "metadata")
  values (create_asset_location.tenant, create_asset_location.parent_id, create_asset_location.kind, trim(create_asset_location.name),
    create_asset_location.code, coalesce(create_asset_location.address, '{}'::jsonb), create_asset_location.latitude,
    create_asset_location.longitude, coalesce(create_asset_location.metadata, '{}'::jsonb))
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage locations' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_asset_location.patch) is distinct from 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'ASSETS_PATCH_INVALID';
  end if;
  if update_asset_location.patch ? 'area' and jsonb_typeof(update_asset_location.patch -> 'area') <> 'null' then
    raise exception 'areas need blocks.assets.options.postgis' using errcode = '55000', hint = 'ASSETS_POSTGIS_REQUIRED';
  end if;
  if update_asset_location.patch ? 'code' and update_asset_location.patch ->> 'code' is not null and exists (
    select 1 from "better_supabase"."asset_locations" x where x."org_id" = v_row."org_id" and x."code" = update_asset_location.patch ->> 'code' and x."id" <> v_row."id"
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.manage'), false)) then
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.read'), false)) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'parentId', v_row."parent_id", 'kind', v_row."kind", 'name', v_row."name", 'code', v_row."code", 'address', v_row."address", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'area', null::jsonb, 'metadata', v_row."metadata", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
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
    select jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'parentId', x."parent_id", 'kind', x."kind", 'name', x."name", 'code', x."code", 'address', x."address", 'latitude', x."latitude", 'longitude', x."longitude", 'area', null::jsonb, 'metadata', x."metadata", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."name" as name, x."id" as id
    from "better_supabase"."asset_locations" x
    where x."org_id" = list_asset_locations.tenant
      and x."parent_id" is not distinct from list_asset_locations.parent_id
      and (coalesce(list_asset_locations.include_archived, false) or x."archived_at" is null)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."org_id", 'assets.read'), false))
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
    select 1 from "better_supabase"."asset_locations" y where y."id" = create_asset.location_id and y."org_id" = create_asset.tenant and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  if create_asset.tag is not null and exists (
    select 1 from "better_supabase"."assets" x where x."org_id" = create_asset.tenant and x."tag" = create_asset.tag
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  insert into "better_supabase"."assets" ("org_id", "location_id", "kind", "name", "tag", "serial_number", "latitude", "longitude", "metadata", "created_by")
  values (create_asset.tenant, create_asset.location_id, create_asset.kind, trim(create_asset.name), create_asset.tag,
    create_asset.serial_number, create_asset.latitude, create_asset.longitude, coalesce(create_asset.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
end;
$$;
revoke execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) from public, anon;
grant execute on function "better_supabase"."create_asset"(uuid, text, text, uuid, text, text, double precision, double precision, jsonb) to authenticated, service_role;

-- Changes the keys patch names: kind, name, locationId, tag, serialNumber,
-- status, latitude, longitude and metadata, and the book value keys
-- acquisitionCost, currency, acquiredOn, usefulLifeMonths, residualValue,
-- depreciationMethod and depreciationRateBps. Retiring an asset releases it.
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if jsonb_typeof(update_asset.patch) is distinct from 'object' then
    raise exception 'patch must be an object' using errcode = '22023', hint = 'ASSETS_PATCH_INVALID';
  end if;
  v_location := case when update_asset.patch ? 'locationId' then (update_asset.patch ->> 'locationId')::uuid else v_row."location_id" end;
  if v_location is distinct from v_row."location_id" then
    if v_location is not null and not exists (
    select 1 from "better_supabase"."asset_locations" y where y."id" = v_location and y."org_id" = v_row."org_id" and y."archived_at" is null
  ) then
    raise exception 'location not found' using errcode = 'P0002', hint = 'ASSETS_LOCATION_NOT_FOUND';
  end if;
  end if;
  v_status := case when update_asset.patch ? 'status' then update_asset.patch ->> 'status' else v_row."status" end;
  if update_asset.patch ? 'tag' and update_asset.patch ->> 'tag' is not null and exists (
    select 1 from "better_supabase"."assets" x where x."org_id" = v_row."org_id" and x."tag" = update_asset.patch ->> 'tag' and x."id" <> v_row."id"
  ) then
    raise exception 'an asset with this tag already exists' using errcode = '23505', hint = 'ASSETS_TAG_TAKEN';
  end if;
  if v_status = 'retired' and v_row."status" <> 'retired' then
    update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  end if;
  if v_row."disposed_on" is not null and (
    update_asset.patch ?| array['acquisitionCost', 'currency', 'acquiredOn', 'usefulLifeMonths', 'residualValue', 'depreciationMethod', 'depreciationRateBps'] or coalesce(update_asset.patch ->> 'status', 'retired') <> 'retired'
  ) then
    raise exception 'a disposed asset stays retired and its book value can''t change' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if update_asset.patch ? 'currency' and not update_asset.patch ? 'acquisitionCost' and v_row."acquisition_cost" is not null
    and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency" then
    raise exception 'the amounts are in another currency than the asset''s cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if (
    (update_asset.patch ? 'acquisitionCost' and (update_asset.patch ->> 'acquisitionCost')::bigint is distinct from v_row."acquisition_cost")
    or (update_asset.patch ? 'currency' and upper(update_asset.patch ->> 'currency') is distinct from v_row."currency")
    or (update_asset.patch ? 'acquiredOn' and (update_asset.patch ->> 'acquiredOn')::date is distinct from v_row."acquired_on")
  ) and exists (
    select 1 from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
  ) then
    raise exception 'the cost, currency and acquisition date are fixed once the asset has depreciated' using errcode = '55000', hint = 'ASSETS_DEPRECIATION_STARTED';
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
    "acquisition_cost" = case when update_asset.patch ? 'acquisitionCost' then (update_asset.patch ->> 'acquisitionCost')::bigint else x."acquisition_cost" end,
    "currency" = case when update_asset.patch ? 'currency' then upper(update_asset.patch ->> 'currency') else x."currency" end,
    "acquired_on" = case when update_asset.patch ? 'acquiredOn' then (update_asset.patch ->> 'acquiredOn')::date else x."acquired_on" end,
    "useful_life_months" = case when update_asset.patch ? 'usefulLifeMonths' then (update_asset.patch ->> 'usefulLifeMonths')::integer else x."useful_life_months" end,
    "residual_value" = case when update_asset.patch ? 'residualValue' then coalesce((update_asset.patch ->> 'residualValue')::bigint, 0) else x."residual_value" end,
    "depreciation_method" = case when update_asset.patch ? 'depreciationMethod' then coalesce(update_asset.patch ->> 'depreciationMethod', 'none') else x."depreciation_method" end,
    "depreciation_rate_bps" = case when update_asset.patch ? 'depreciationRateBps' then (update_asset.patch ->> 'depreciationRateBps')::integer else x."depreciation_rate_bps" end,
    "assignee_type" = case when v_status = 'retired' then null else x."assignee_type" end,
    "assignee_id" = case when v_status = 'retired' then null else x."assignee_id" end,
    "retired_at" = case when v_status = 'retired' then coalesce(x."retired_at", now()) else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."acquisition_cost" is not null and v_row."currency" is null then
    raise exception 'an acquisition cost needs a currency' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."residual_value" > coalesce(v_row."acquisition_cost", 0) and v_row."depreciation_method" <> 'none' then
    raise exception 'the residual value is more than the acquisition cost' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" <> 'none' and (v_row."acquisition_cost" is null or v_row."acquired_on" is null) then
    raise exception 'depreciation needs an acquisition cost and date' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'straight_line' and v_row."useful_life_months" is null then
    raise exception 'straight-line depreciation needs a useful life' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  if v_row."depreciation_method" = 'declining_balance' and v_row."depreciation_rate_bps" is null then
    raise exception 'declining-balance depreciation needs a rate' using errcode = '22023', hint = 'ASSETS_DEPRECIATION_INVALID';
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."status" = 'retired' then
    raise exception 'a retired asset can''t be assigned' using errcode = '55000', hint = 'ASSETS_RETIRED';
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_-]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
    raise exception 'an assignee needs a lowercase type and an id' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  if assign_asset.assignee_type = 'member' and (
    assign_asset.assignee_id !~ '^[0-9a-fA-F-]{36}$'
    or not coalesce(better_supabase.can_user(assign_asset.assignee_id::uuid, 'tenant', v_row."org_id", 'assets.read'), false)
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
  insert into "better_supabase"."asset_assignments" ("org_id", "asset_id", "assignee_type", "assignee_id", "note", "assigned_by")
  values (v_row."org_id", v_row."id", assign_asset.assignee_type, assign_asset.assignee_id, nullif(trim(assign_asset.note), ''), auth.uid());
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.assign'), false)) then
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text);
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('acquisitionCost', v_row."acquisition_cost"::text, 'currency', v_row."currency", 'acquiredOn', v_row."acquired_on", 'usefulLifeMonths', v_row."useful_life_months", 'residualValue', v_row."residual_value"::text, 'depreciationMethod', v_row."depreciation_method", 'depreciationRateBps', v_row."depreciation_rate_bps", 'disposedOn', v_row."disposed_on", 'disposalAmount', v_row."disposal_amount"::text) || (select jsonb_build_object('accumulatedDepreciation', q.total::text, 'bookValue', case when v_row."acquisition_cost" is null then null else (v_row."acquisition_cost" - q.total)::text end) from (select coalesce(sum(y."amount"), 0) as total from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id") q) || jsonb_build_object(
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
    select jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, x."created_at" as created_at, x."id" as id
    from "better_supabase"."assets" x
    where (list_assets.tenant is null or x."org_id" = list_assets.tenant)
      and (list_assets.location_id is null or x."location_id" in (select below.id from below))
      and (list_assets.kind is null or x."kind" = list_assets.kind)
      and (list_assets.status is null or x."status" = list_assets.status)
      and (list_assets.assignee_type is null or x."assignee_type" = list_assets.assignee_type)
      and (list_assets.assignee_id is null or x."assignee_id" = list_assets.assignee_id)
      and (list_assets.query is null or x."name" ilike '%' || list_assets.query || '%' or x."tag" = list_assets.query or x."serial_number" = list_assets.query)
      and (list_assets.before is null or x."created_at" < list_assets.before)
      and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', x."org_id", 'assets.read'), false)) or (x."assignee_type" = 'member' and coalesce(x."assignee_id" = auth.uid()::text, false)))
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
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
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
        select jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'locationId', x."location_id", 'kind', x."kind", 'name', x."name", 'tag', x."tag", 'serialNumber', x."serial_number", 'status', x."status", 'assigneeType', x."assignee_type", 'assigneeId', x."assignee_id", 'latitude', x."latitude", 'longitude', x."longitude", 'metadata', x."metadata", 'retiredAt', x."retired_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('acquisitionCost', x."acquisition_cost"::text, 'currency', x."currency", 'acquiredOn', x."acquired_on", 'usefulLifeMonths', x."useful_life_months", 'residualValue', x."residual_value"::text, 'depreciationMethod', x."depreciation_method", 'depreciationRateBps', x."depreciation_rate_bps", 'disposedOn', x."disposed_on", 'disposalAmount', x."disposal_amount"::text) as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
        from "better_supabase"."assets" x
        where x."org_id" = assets_near.tenant and x."latitude" is not null and x."status" <> 'retired'
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
        select jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'parentId', x."parent_id", 'kind', x."kind", 'name', x."name", 'code', x."code", 'address', x."address", 'latitude', x."latitude", 'longitude', x."longitude", 'area', null::jsonb, 'metadata', x."metadata", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, (2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(x."latitude" - assets_near.latitude) / 2), 2) + cos(radians(assets_near.latitude)) * cos(radians(x."latitude")) * power(sin(radians(x."longitude" - assets_near.longitude) / 2), 2))))) as distance, x."id" as id
        from "better_supabase"."asset_locations" x
        where x."org_id" = assets_near.tenant and x."latitude" is not null and x."archived_at" is null
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
  raise exception 'install bookings or tasks to link assets' using errcode = '22023', hint = 'ASSETS_LINK_UNSUPPORTED';
end;
$$;
revoke execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."set_asset_link"(text, uuid, uuid) to authenticated, service_role;


-- Books an asset's depreciation for every month that ended on or before
-- until, from the month it was acquired in and stopping at the month it was
-- disposed of in. Straight line spreads the cost less the residual value over
-- the useful life; declining balance takes the yearly rate of the book value,
-- and writes the rest down at the end of the useful life when there is one.
-- A month books what the method has reached less what is booked, so a changed
-- life or residual value catches up in the next month. Returns the months
-- booked.
create or replace function "better_supabase"."asset_depreciate"(asset_id uuid, until date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_asset "better_supabase"."assets"%rowtype;
  v_row "better_supabase"."asset_depreciations"%rowtype;
  v_start date;
  v_month date;
  v_last date;
  v_booked bigint;
  v_base bigint;
  v_age integer;
  v_amount bigint;
  v_count integer := 0;
begin
  select * into v_asset from "better_supabase"."assets" x where x."id" = asset_depreciate.asset_id for update;
  if not found or v_asset."depreciation_method" = 'none'
    or v_asset."acquisition_cost" is null or v_asset."acquired_on" is null then
    return 0;
  end if;
  select max(y."period_start"), coalesce(sum(y."amount"), 0) into v_last, v_booked
  from "better_supabase"."asset_depreciations" y where y."asset_id" = v_asset."id";
  v_start := date_trunc('month', v_asset."acquired_on")::date;
  v_month := coalesce((v_last + interval '1 month')::date, v_start);
  v_base := v_asset."acquisition_cost" - v_asset."residual_value";
  while (v_month + interval '1 month' - interval '1 day')::date <= asset_depreciate.until
    and (v_asset."disposed_on" is null or v_month < date_trunc('month', v_asset."disposed_on")::date)
    and v_booked < v_base loop
    v_age := ((extract(year from v_month) - extract(year from v_start)) * 12 + extract(month from v_month) - extract(month from v_start))::integer + 1;
    if v_asset."depreciation_method" = 'straight_line' then
      v_amount := least(v_base, round(v_base::numeric * v_age / v_asset."useful_life_months")::bigint) - v_booked;
    elsif v_asset."useful_life_months" is not null and v_age >= v_asset."useful_life_months" then
      v_amount := v_base - v_booked;
    else
      v_amount := least(v_base - v_booked, round((v_asset."acquisition_cost" - v_booked)::numeric * v_asset."depreciation_rate_bps" / 120000)::bigint);
    end if;
    if v_amount > 0 then
      insert into "better_supabase"."asset_depreciations" ("org_id", "asset_id", "period_start", "amount")
      values (v_asset."org_id", v_asset."id", v_month, v_amount)
      returning * into v_row;
      null;
      v_booked := v_booked + v_amount;
      v_count := v_count + 1;
    end if;
    v_month := (v_month + interval '1 month')::date;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."asset_depreciate"(uuid, date) from public, anon, authenticated;

-- Books depreciation up to until (default today) for every asset in service
-- of an organization, or of every organization with tenant null. Run it
-- monthly from a scheduled job; it books each month once.
create or replace function "better_supabase"."run_asset_depreciation"(tenant uuid default null, until date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_until date := coalesce(run_asset_depreciation.until, current_date);
  v_id uuid;
  v_months integer;
  v_assets integer := 0;
  v_total integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'only the service role runs depreciation' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  for v_id in
    select x."id" from "better_supabase"."assets" x
    where (run_asset_depreciation.tenant is null or x."org_id" = run_asset_depreciation.tenant)
      and x."depreciation_method" <> 'none' and x."disposed_on" is null
    order by x."org_id", x."id"
  loop
    v_months := "better_supabase"."asset_depreciate"(v_id, v_until);
    if v_months > 0 then
      v_assets := v_assets + 1;
      v_total := v_total + v_months;
    end if;
  end loop;
  return jsonb_build_object('until', v_until, 'assets', v_assets, 'months', v_total);
end;
$$;
revoke execute on function "better_supabase"."run_asset_depreciation"(uuid, date) from public, anon, authenticated;
grant execute on function "better_supabase"."run_asset_depreciation"(uuid, date) to service_role;

-- Takes an asset off the books on disposed_on for amount, the proceeds in
-- currency (the asset's): books depreciation through the month before, then
-- retires and releases the asset and books the disposal, the proceeds less
-- the book value being a gain or a loss.
create or replace function "better_supabase"."dispose_asset"(asset_id uuid, disposed_on date, amount bigint default 0, currency text default null)
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
  select * into v_row from "better_supabase"."assets" x where x."id" = dispose_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.manage'), false)) then
    raise exception 'not allowed to manage assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."disposed_on" is not null then
    raise exception 'the asset is already disposed of' using errcode = '55000', hint = 'ASSETS_DISPOSED';
  end if;
  if dispose_asset.disposed_on is null or coalesce(dispose_asset.amount, 0) < 0
    or dispose_asset.disposed_on < coalesce(v_row."acquired_on", dispose_asset.disposed_on) then
    raise exception 'a disposal needs a date on or after the acquisition and proceeds of 0 or more' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  if coalesce(dispose_asset.amount, 0) > 0 and (
    v_row."currency" is null or upper(coalesce(dispose_asset.currency, v_row."currency")) <> v_row."currency"
  ) then
    raise exception 'the proceeds need to be in the asset''s currency' using errcode = '22023', hint = 'ASSETS_DISPOSAL_INVALID';
  end if;
  perform "better_supabase"."asset_depreciate"(v_row."id", (date_trunc('month', dispose_asset.disposed_on) - interval '1 day')::date);
  update "better_supabase"."asset_assignments" y set "released_at" = now()
  where y."asset_id" = v_row."id" and y."released_at" is null;
  update "better_supabase"."assets" x set
    "disposed_on" = dispose_asset.disposed_on,
    "disposal_amount" = coalesce(dispose_asset.amount, 0),
    "status" = 'retired',
    "assignee_type" = null,
    "assignee_id" = null,
    "retired_at" = coalesce(x."retired_at", now()),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return "better_supabase"."get_asset"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."dispose_asset"(uuid, date, bigint, text) from public, anon;
grant execute on function "better_supabase"."dispose_asset"(uuid, date, bigint, text) to authenticated, service_role;

-- An asset's depreciation, oldest month first.
create or replace function "better_supabase"."list_asset_depreciations"(asset_id uuid, page_size integer default 600)
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
  select * into v_row from "better_supabase"."assets" x where x."id" = list_asset_depreciations.asset_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and coalesce(v_row."assignee_id" = auth.uid()::text, false))) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."org_id", 'assetId', q."asset_id", 'periodStart', q."period_start", 'amount', q."amount"::text, 'currency', v_row."currency", 'entryId', q."entry_id", 'createdAt', q."created_at") order by q."period_start"), '[]'::jsonb)
    from (
      select * from "better_supabase"."asset_depreciations" y where y."asset_id" = v_row."id"
      order by y."period_start"
      limit greatest(1, least(coalesce(list_asset_depreciations.page_size, 600), 1200))
    ) q
  );
end;
$$;
revoke execute on function "better_supabase"."list_asset_depreciations"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_asset_depreciations"(uuid, integer) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_locations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_select on "better_supabase"."asset_locations" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('assets.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_locations" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_update on "better_supabase"."asset_locations" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_locations";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_locations" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."assets";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."assets";
create policy bsb_tenant_scope_select on "better_supabase"."assets" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('assets.read'))
    or ("assignee_type" = 'member' and "assignee_id" = (select auth.uid())::text))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."assets";
create policy bsb_tenant_scope_insert on "better_supabase"."assets" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."assets";
create policy bsb_tenant_scope_update on "better_supabase"."assets" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."assets";
create policy bsb_tenant_scope_delete on "better_supabase"."assets" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_assignments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_select on "better_supabase"."asset_assignments" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("asset_id" in (select y."id" from "better_supabase"."assets" y))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_assignments" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_update on "better_supabase"."asset_assignments" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_assignments";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_assignments" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."asset_depreciations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_select on "better_supabase"."asset_depreciations" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('assets.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_insert on "better_supabase"."asset_depreciations" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_update on "better_supabase"."asset_depreciations" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."asset_depreciations";
create policy bsb_tenant_scope_delete on "better_supabase"."asset_depreciations" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_114_assets.sql
-- better-supabase module: assets
-- @bsb-block-data assets
-- @bsb-hash sha256:cdfee733cdb1ab16291963d28940f13d8d33a1ba53dbbfb6af72eed615bd1cdf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('assets', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
