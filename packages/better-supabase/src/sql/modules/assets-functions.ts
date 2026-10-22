import type { BlockSqlContext } from "../context.ts";

import { fail, pageSize, SERVICE_CALLER, userGrant } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** Whether the module stores points and areas as PostGIS geography (ADR 0066). */
export const assetsPostgis = (ctx: BlockSqlContext): boolean =>
  ctx.flag("postgis", false);

/** `geography` qualified with the schema PostGIS is installed in. */
export const GEOGRAPHY = "extensions.geography";

/** A geography point from latitude and longitude columns or expressions. */
export const geographyPoint = (latitude: string, longitude: string): string =>
  `extensions.st_setsrid(extensions.st_makepoint(${longitude}, ${latitude}), 4326)::${GEOGRAPHY}`;

/** The great-circle distance in meters between two points (haversine). */
const haversine = (
  lat1: string,
  lng1: string,
  lat2: string,
  lng2: string,
): string =>
  `(2 * 6371008.8 * asin(least(1, sqrt(power(sin(radians(${lat2} - ${lat1}) / 2), 2) + cos(radians(${lat1})) * cos(radians(${lat2})) * power(sin(radians(${lng2} - ${lng1}) / 2), 2)))))`;

/** The assets module's functions. */
export function assetsFunctions(ctx: BlockSqlContext): string {
  const locations = ctx.table("locations");
  const assets = ctx.table("assets");
  const assignments = ctx.table("assignments");
  const l = (column: string): string => ctx.col("locations", column);
  const s = (column: string): string => ctx.col("assets", column);
  const g = (column: string): string => ctx.col("assignments", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("assets");
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const assign = ctx.permission("assign", permissions.assign);
  const postgis = assetsPostgis(ctx);

  const bookings =
    ctx.installed("bookings") && ctx.of("bookings").manages
      ? ctx.of("bookings")
      : undefined;

  const workItems =
    ctx.installed("tasks") && ctx.of("tasks").manages
      ? ctx.of("tasks")
      : undefined;

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const readsLocation = (row: string): string =>
    allowed(`${row}.${l("tenant")}`, read);

  const readsAsset = (row: string): string =>
    `(${allowed(`${row}.${s("tenant")}`, read)} or (${row}.${s("assigneeType")} = 'member' and ${row}.${s("assigneeId")} = auth.uid()::text))`;

  const forbidden = (message: string): string =>
    fail("ASSETS_FORBIDDEN", message);

  const invalid = (code: string, message: string): string =>
    fail(code, message, "22023");

  const locationMissing = fail(
    "ASSETS_LOCATION_NOT_FOUND",
    "location not found",
    "P0002",
  );

  const assetMissing = fail("ASSETS_NOT_FOUND", "asset not found", "P0002");

  const needsPostgis = fail(
    "ASSETS_POSTGIS_REQUIRED",
    "areas need blocks.assets.options.postgis",
    "55000",
  );

  const area = (geojson: string): string =>
    `extensions.st_multi(extensions.st_setsrid(extensions.st_geomfromgeojson(${geojson}::text), 4326))::extensions.geography`;

  const locationJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${l("id")}, 'organizationId', ${row}.${l("tenant")}, 'parentId', ${row}.${l("parent")}, 'kind', ${row}.${l("kind")}, 'name', ${row}.${l("name")}, 'code', ${row}.${l("code")}, 'address', ${row}.${l("address")}, 'latitude', ${row}.${l("latitude")}, 'longitude', ${row}.${l("longitude")}, 'area', ${postgis ? `extensions.st_asgeojson(${row}.area::extensions.geometry)::jsonb` : "null::jsonb"}, 'metadata', ${row}.${l("metadata")}, 'archivedAt', ${row}.${l("archivedAt")}, 'createdAt', ${row}.${l("createdAt")}, 'updatedAt', ${row}.${l("updatedAt")})`;

  const assetJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'locationId', ${row}.${s("location")}, 'kind', ${row}.${s("kind")}, 'name', ${row}.${s("name")}, 'tag', ${row}.${s("tag")}, 'serialNumber', ${row}.${s("serial")}, 'status', ${row}.${s("status")}, 'assigneeType', ${row}.${s("assigneeType")}, 'assigneeId', ${row}.${s("assigneeId")}, 'latitude', ${row}.${s("latitude")}, 'longitude', ${row}.${s("longitude")}, 'metadata', ${row}.${s("metadata")}, 'retiredAt', ${row}.${s("retiredAt")}, 'createdBy', ${row}.${s("createdBy")}, 'createdAt', ${row}.${s("createdAt")}, 'updatedAt', ${row}.${s("updatedAt")})`;

  const assignmentJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${g("id")}, 'assetId', ${row}.${g("asset")}, 'assigneeType', ${row}.${g("assigneeType")}, 'assigneeId', ${row}.${g("assigneeId")}, 'note', ${row}.${g("note")}, 'assignedBy', ${row}.${g("assignedBy")}, 'assignedAt', ${row}.${g("assignedAt")}, 'releasedAt', ${row}.${g("releasedAt")})`;

  const locationRecord = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${l("tenant")}, 'id', ${row}.${l("id")}, 'kind', ${row}.${l("kind")}, 'name', ${row}.${l("name")}, 'parentId', ${row}.${l("parent")})`,
      subject: `'asset-locations/' || ${row}.${l("id")}::text`,
      tenant: `${row}.${l("tenant")}`,
      audit: {
        category: "data",
        targetType: "asset_location",
        recordId: `${row}.${l("id")}::text`,
        targetLabel: `${row}.${l("name")}`,
        summary: `'${summary}'`,
      },
    });

  const assetRecord = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${s("tenant")}, 'id', ${row}.${s("id")}, 'kind', ${row}.${s("kind")}, 'name', ${row}.${s("name")}, 'status', ${row}.${s("status")}, 'locationId', ${row}.${s("location")}, 'assigneeType', ${row}.${s("assigneeType")}, 'assigneeId', ${row}.${s("assigneeId")})`,
      subject: `'assets/' || ${row}.${s("id")}::text`,
      tenant: `${row}.${s("tenant")}`,
      audit: {
        category: "data",
        targetType: "asset",
        recordId: `${row}.${s("id")}::text`,
        targetLabel: `${row}.${s("name")}`,
        summary: `'${summary}'`,
      },
    });

  const checkLocation = (tenant: string, location: string): string =>
    `if ${location} is not null and not exists (
    select 1 from ${locations} y where y.${l("id")} = ${location} and y.${l("tenant")} = ${tenant} and y.${l("archivedAt")} is null
  ) then
    ${locationMissing}
  end if;`;

  const releaseOpen = (asset: string): string =>
    `update ${assignments} y set ${g("releasedAt")} = now()
    where y.${g("asset")} = ${asset} and y.${g("releasedAt")} is null;`;

  const pathOf = (location: string): string =>
    `coalesce((
    with recursive up as (
      select y.${l("id")} as id, y.${l("parent")} as parent, y.${l("kind")} as kind, y.${l("name")} as name, 0 as depth from ${locations} y where y.${l("id")} = ${location}
      union all
      select y.${l("id")}, y.${l("parent")}, y.${l("kind")}, y.${l("name")}, up.depth + 1 from ${locations} y join up on y.${l("id")} = up.parent where up.depth < 64
    )
    select jsonb_agg(jsonb_build_object('id', up.id, 'kind', up.kind, 'name', up.name) order by up.depth desc) from up
  ), '[]'::jsonb)`;

  const links = (asset: string): string => {
    const parts = [
      bookings
        ? `'bookingResources', coalesce((select jsonb_agg(jsonb_build_object('id', y.${bookings.col("resources", "id")}, 'name', y.${bookings.col("resources", "name")}) order by y.${bookings.col("resources", "name")}) from ${bookings.table("resources")} y where y.asset_id = ${asset}), '[]'::jsonb)`
        : `'bookingResources', '[]'::jsonb`,
      workItems
        ? `'workItems', coalesce((select jsonb_agg(jsonb_build_object('id', z.id, 'title', z.title) order by z.created_at desc) from (select y.${workItems.col("items", "id")} as id, y.${workItems.col("items", "title")} as title, y.${workItems.col("items", "createdAt")} as created_at from ${workItems.table("items")} y where y.asset_id = ${asset} and y.${workItems.col("items", "closedAt")} is null order by y.${workItems.col("items", "createdAt")} desc limit 50) z), '[]'::jsonb)`
        : `'workItems', '[]'::jsonb`,
    ];

    return `jsonb_build_object(${parts.join(", ")})`;
  };

  const linkTargets = [
    bookings
      ? `when 'booking_resource' then
    select y.${bookings.col("resources", "tenant")} into v_tenant from ${bookings.table("resources")} y where y.${bookings.col("resources", "id")} = set_asset_link.target_id;`
      : "",
    workItems
      ? `when 'work_item' then
    select y.${workItems.col("items", "tenant")} into v_tenant from ${workItems.table("items")} y where y.${workItems.col("items", "id")} = set_asset_link.target_id;`
      : "",
  ].filter((part) => part !== "");

  const linkWrites = [
    bookings
      ? `if set_asset_link.target_type = 'booking_resource' then
    update ${bookings.table("resources")} y set asset_id = set_asset_link.asset_id where y.${bookings.col("resources", "id")} = set_asset_link.target_id;
  end if;`
      : "",
    workItems
      ? `if set_asset_link.target_type = 'work_item' then
    update ${workItems.table("items")} y set asset_id = set_asset_link.asset_id where y.${workItems.col("items", "id")} = set_asset_link.target_id;
  end if;`
      : "",
  ].filter((part) => part !== "");

  const near = (row: string, table: "locations" | "assets"): string => {
    const col = table === "locations" ? l : s;

    return postgis
      ? `extensions.st_dwithin(${row}.point, v_point, assets_near.radius_meters)`
      : `${row}.${col("latitude")} between assets_near.latitude - v_dlat and assets_near.latitude + v_dlat
        and ${row}.${col("longitude")} between assets_near.longitude - v_dlng and assets_near.longitude + v_dlng
        and ${haversine("assets_near.latitude", "assets_near.longitude", `${row}.${col("latitude")}`, `${row}.${col("longitude")}`)} <= assets_near.radius_meters`;
  };

  const distance = (row: string, table: "locations" | "assets"): string => {
    const col = table === "locations" ? l : s;

    return postgis
      ? `extensions.st_distance(${row}.point, v_point)`
      : haversine(
          "assets_near.latitude",
          "assets_near.longitude",
          `${row}.${col("latitude")}`,
          `${row}.${col("longitude")}`,
        );
  };

  const locationArgs = `${idType}, text, text, uuid, text, jsonb, double precision, double precision, jsonb, jsonb`;
  const assetArgs = `${idType}, text, text, uuid, text, text, double precision, double precision, jsonb`;
  const listArgs = `${idType}, uuid, boolean, text, text, text, text, text, timestamptz, integer`;

  return `-- Adds a location (a site, building, floor, unit or room) under parent_id,
-- or at the top when it is null. area is GeoJSON and needs the postgis option.
create or replace function ${fn("create_asset_location")}(tenant ${idType}, kind text, name text, parent_id uuid default null, code text default null, address jsonb default null, latitude double precision default null, longitude double precision default null, area jsonb default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${locations}%rowtype;
begin
  if not ${allowed("create_asset_location.tenant", manage)} then
    ${forbidden("not allowed to manage locations")}
  end if;
  ${postgis ? "" : `if create_asset_location.area is not null then\n    ${needsPostgis}\n  end if;`}
  if create_asset_location.code is not null and exists (
    select 1 from ${locations} x where x.${l("tenant")} = create_asset_location.tenant and x.${l("code")} = create_asset_location.code
  ) then
    ${fail("ASSETS_CODE_TAKEN", "a location with this code already exists", "23505")}
  end if;
  insert into ${locations} (${l("tenant")}, ${l("parent")}, ${l("kind")}, ${l("name")}, ${l("code")}, ${l("address")}, ${l("latitude")}, ${l("longitude")}, ${postgis ? "area, " : ""}${l("metadata")})
  values (create_asset_location.tenant, create_asset_location.parent_id, create_asset_location.kind, trim(create_asset_location.name),
    create_asset_location.code, coalesce(create_asset_location.address, '{}'::jsonb), create_asset_location.latitude,
    create_asset_location.longitude, ${postgis ? `case when create_asset_location.area is null then null else ${area("create_asset_location.area")} end, ` : ""}coalesce(create_asset_location.metadata, '{}'::jsonb))
  returning * into v_row;
  ${locationRecord("asset_location.created", "v_row", "created location")}
  return ${locationJson("v_row")};
end;
$$;
${userGrant(`${fn("create_asset_location")}(${locationArgs})`)}

-- Changes the keys patch names: kind, name, parentId, code, address,
-- latitude, longitude, area and metadata. A null value clears an optional key.
create or replace function ${fn("update_asset_location")}(location_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${locations}%rowtype;
begin
  select * into v_row from ${locations} x where x.${l("id")} = update_asset_location.location_id for update;
  if not found or not ${readsLocation("v_row")} then
    ${locationMissing}
  end if;
  if not ${allowed(`v_row.${l("tenant")}`, manage)} then
    ${forbidden("not allowed to manage locations")}
  end if;
  if jsonb_typeof(update_asset_location.patch) is distinct from 'object' then
    ${invalid("ASSETS_PATCH_INVALID", "patch must be an object")}
  end if;
  ${postgis ? "" : `if update_asset_location.patch ? 'area' and jsonb_typeof(update_asset_location.patch -> 'area') <> 'null' then\n    ${needsPostgis}\n  end if;`}
  if update_asset_location.patch ? 'code' and update_asset_location.patch ->> 'code' is not null and exists (
    select 1 from ${locations} x where x.${l("tenant")} = v_row.${l("tenant")} and x.${l("code")} = update_asset_location.patch ->> 'code' and x.${l("id")} <> v_row.${l("id")}
  ) then
    ${fail("ASSETS_CODE_TAKEN", "a location with this code already exists", "23505")}
  end if;
  update ${locations} x set
    ${l("kind")} = case when update_asset_location.patch ? 'kind' then update_asset_location.patch ->> 'kind' else x.${l("kind")} end,
    ${l("name")} = case when update_asset_location.patch ? 'name' then trim(update_asset_location.patch ->> 'name') else x.${l("name")} end,
    ${l("parent")} = case when update_asset_location.patch ? 'parentId' then (update_asset_location.patch ->> 'parentId')::uuid else x.${l("parent")} end,
    ${l("code")} = case when update_asset_location.patch ? 'code' then update_asset_location.patch ->> 'code' else x.${l("code")} end,
    ${l("address")} = case when update_asset_location.patch ? 'address' then coalesce(nullif(update_asset_location.patch -> 'address', 'null'::jsonb), '{}'::jsonb) else x.${l("address")} end,
    ${l("latitude")} = case when update_asset_location.patch ? 'latitude' then (update_asset_location.patch ->> 'latitude')::double precision else x.${l("latitude")} end,
    ${l("longitude")} = case when update_asset_location.patch ? 'longitude' then (update_asset_location.patch ->> 'longitude')::double precision else x.${l("longitude")} end,
    ${postgis ? `area = case when update_asset_location.patch ? 'area' then case when jsonb_typeof(update_asset_location.patch -> 'area') = 'null' then null else ${area("(update_asset_location.patch -> 'area')")} end else x.area end,\n    ` : ""}${l("metadata")} = case when update_asset_location.patch ? 'metadata' then coalesce(nullif(update_asset_location.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x.${l("metadata")} end,
    ${l("updatedAt")} = now()
  where x.${l("id")} = v_row.${l("id")}
  returning * into v_row;
  ${locationRecord("asset_location.updated", "v_row", "updated location")}
  return ${locationJson("v_row")};
end;
$$;
${userGrant(`${fn("update_asset_location")}(uuid, jsonb)`)}

-- Archives a location with no open sublocations and no assets in service.
create or replace function ${fn("archive_asset_location")}(location_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${locations}%rowtype;
begin
  select * into v_row from ${locations} x where x.${l("id")} = archive_asset_location.location_id for update;
  if not found or not ${readsLocation("v_row")} then
    ${locationMissing}
  end if;
  if not ${allowed(`v_row.${l("tenant")}`, manage)} then
    ${forbidden("not allowed to manage locations")}
  end if;
  if exists (select 1 from ${locations} y where y.${l("parent")} = v_row.${l("id")} and y.${l("archivedAt")} is null)
    or exists (select 1 from ${assets} y where y.${s("location")} = v_row.${l("id")} and y.${s("status")} <> 'retired') then
    ${fail("ASSETS_LOCATION_IN_USE", "move or archive the sublocations and assets of this location first", "55000")}
  end if;
  if v_row.${l("archivedAt")} is null then
    update ${locations} x set ${l("archivedAt")} = now(), ${l("updatedAt")} = now()
      where x.${l("id")} = v_row.${l("id")}
      returning * into v_row;
    ${locationRecord("asset_location.archived", "v_row", "archived location")}
  end if;
  return ${locationJson("v_row")};
end;
$$;
${userGrant(`${fn("archive_asset_location")}(uuid)`)}

-- A location with its path from the top (path ends with the location itself)
-- and how many sublocations and assets it holds.
create or replace function ${fn("get_asset_location")}(location_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${locations}%rowtype;
begin
  select * into v_row from ${locations} x where x.${l("id")} = get_asset_location.location_id;
  if not found or not ${readsLocation("v_row")} then
    ${locationMissing}
  end if;
  return ${locationJson("v_row")} || jsonb_build_object(
    'path', ${pathOf(`v_row.${l("id")}`)},
    'locations', (select count(*)::integer from ${locations} y where y.${l("parent")} = v_row.${l("id")} and y.${l("archivedAt")} is null),
    'assets', (select count(*)::integer from ${assets} y where y.${s("location")} = v_row.${l("id")} and y.${s("status")} <> 'retired'));
end;
$$;
${userGrant(`${fn("get_asset_location")}(uuid)`)}

-- The locations directly under parent_id, or the top ones when it is null.
create or replace function ${fn("list_asset_locations")}(tenant ${idType}, parent_id uuid default null, include_archived boolean default false, page_size integer default 200)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.item order by z.name, z.id), '[]'::jsonb)
  from (
    select ${locationJson("x")} as item, x.${l("name")} as name, x.${l("id")} as id
    from ${locations} x
    where x.${l("tenant")} = list_asset_locations.tenant
      and x.${l("parent")} is not distinct from list_asset_locations.parent_id
      and (coalesce(list_asset_locations.include_archived, false) or x.${l("archivedAt")} is null)
      and ${readsLocation("x")}
    order by x.${l("name")}, x.${l("id")}
    limit ${pageSize("list_asset_locations.page_size", 200, 1000)}
  ) z
$$;
${userGrant(`${fn("list_asset_locations")}(${idType}, uuid, boolean, integer)`)}

-- Registers an asset, at location_id when given.
create or replace function ${fn("create_asset")}(tenant ${idType}, kind text, name text, location_id uuid default null, tag text default null, serial_number text default null, latitude double precision default null, longitude double precision default null, metadata jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${assets}%rowtype;
begin
  if not ${allowed("create_asset.tenant", manage)} then
    ${forbidden("not allowed to manage assets")}
  end if;
  ${checkLocation("create_asset.tenant", "create_asset.location_id")}
  if create_asset.tag is not null and exists (
    select 1 from ${assets} x where x.${s("tenant")} = create_asset.tenant and x.${s("tag")} = create_asset.tag
  ) then
    ${fail("ASSETS_TAG_TAKEN", "an asset with this tag already exists", "23505")}
  end if;
  insert into ${assets} (${s("tenant")}, ${s("location")}, ${s("kind")}, ${s("name")}, ${s("tag")}, ${s("serial")}, ${s("latitude")}, ${s("longitude")}, ${s("metadata")}, ${s("createdBy")})
  values (create_asset.tenant, create_asset.location_id, create_asset.kind, trim(create_asset.name), create_asset.tag,
    create_asset.serial_number, create_asset.latitude, create_asset.longitude, coalesce(create_asset.metadata, '{}'::jsonb), auth.uid())
  returning * into v_row;
  ${assetRecord("asset.created", "v_row", "created asset")}
  return ${assetJson("v_row")};
end;
$$;
${userGrant(`${fn("create_asset")}(${assetArgs})`)}

-- Changes the keys patch names: kind, name, locationId, tag, serialNumber,
-- status, latitude, longitude and metadata. Retiring an asset releases it.
create or replace function ${fn("update_asset")}(asset_id uuid, patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${assets}%rowtype;
  v_location uuid;
  v_status text;
begin
  select * into v_row from ${assets} x where x.${s("id")} = update_asset.asset_id for update;
  if not found or not ${readsAsset("v_row")} then
    ${assetMissing}
  end if;
  if not ${allowed(`v_row.${s("tenant")}`, manage)} then
    ${forbidden("not allowed to manage assets")}
  end if;
  if jsonb_typeof(update_asset.patch) is distinct from 'object' then
    ${invalid("ASSETS_PATCH_INVALID", "patch must be an object")}
  end if;
  v_location := case when update_asset.patch ? 'locationId' then (update_asset.patch ->> 'locationId')::uuid else v_row.${s("location")} end;
  if v_location is distinct from v_row.${s("location")} then
    ${checkLocation(`v_row.${s("tenant")}`, "v_location")}
  end if;
  v_status := case when update_asset.patch ? 'status' then update_asset.patch ->> 'status' else v_row.${s("status")} end;
  if update_asset.patch ? 'tag' and update_asset.patch ->> 'tag' is not null and exists (
    select 1 from ${assets} x where x.${s("tenant")} = v_row.${s("tenant")} and x.${s("tag")} = update_asset.patch ->> 'tag' and x.${s("id")} <> v_row.${s("id")}
  ) then
    ${fail("ASSETS_TAG_TAKEN", "an asset with this tag already exists", "23505")}
  end if;
  if v_status = 'retired' and v_row.${s("status")} <> 'retired' then
    ${releaseOpen(`v_row.${s("id")}`)}
  end if;
  update ${assets} x set
    ${s("kind")} = case when update_asset.patch ? 'kind' then update_asset.patch ->> 'kind' else x.${s("kind")} end,
    ${s("name")} = case when update_asset.patch ? 'name' then trim(update_asset.patch ->> 'name') else x.${s("name")} end,
    ${s("location")} = v_location,
    ${s("tag")} = case when update_asset.patch ? 'tag' then update_asset.patch ->> 'tag' else x.${s("tag")} end,
    ${s("serial")} = case when update_asset.patch ? 'serialNumber' then update_asset.patch ->> 'serialNumber' else x.${s("serial")} end,
    ${s("status")} = v_status,
    ${s("latitude")} = case when update_asset.patch ? 'latitude' then (update_asset.patch ->> 'latitude')::double precision else x.${s("latitude")} end,
    ${s("longitude")} = case when update_asset.patch ? 'longitude' then (update_asset.patch ->> 'longitude')::double precision else x.${s("longitude")} end,
    ${s("metadata")} = case when update_asset.patch ? 'metadata' then coalesce(nullif(update_asset.patch -> 'metadata', 'null'::jsonb), '{}'::jsonb) else x.${s("metadata")} end,
    ${s("assigneeType")} = case when v_status = 'retired' then null else x.${s("assigneeType")} end,
    ${s("assigneeId")} = case when v_status = 'retired' then null else x.${s("assigneeId")} end,
    ${s("retiredAt")} = case when v_status = 'retired' then coalesce(x.${s("retiredAt")}, now()) else null end,
    ${s("updatedAt")} = now()
  where x.${s("id")} = v_row.${s("id")}
  returning * into v_row;
  ${assetRecord("asset.updated", "v_row", "updated asset")}
  return ${assetJson("v_row")};
end;
$$;
${userGrant(`${fn("update_asset")}(uuid, jsonb)`)}

-- Assigns an asset to a member (assignee_type member, a user id) or to a
-- record such as a party. The previous assignment ends.
create or replace function ${fn("assign_asset")}(asset_id uuid, assignee_type text, assignee_id text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${assets}%rowtype;
begin
  select * into v_row from ${assets} x where x.${s("id")} = assign_asset.asset_id for update;
  if not found or not ${readsAsset("v_row")} then
    ${assetMissing}
  end if;
  if not ${allowed(`v_row.${s("tenant")}`, assign)} then
    ${forbidden("not allowed to assign assets")}
  end if;
  if v_row.${s("status")} = 'retired' then
    ${fail("ASSETS_RETIRED", "a retired asset can't be assigned", "55000")}
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
    ${invalid("ASSETS_ASSIGNEE_INVALID", "an assignee needs a lowercase type and an id")}
  end if;
  if assign_asset.assignee_type = 'member' and (
    assign_asset.assignee_id !~ '^[0-9a-fA-F-]{36}$'
    or not ${ctx.scope.canUser("assign_asset.assignee_id::uuid", `v_row.${s("tenant")}`, read)}
  ) then
    ${invalid("ASSETS_ASSIGNEE_INVALID", "the member can't see this organization's assets")}
  end if;
  ${ctx.hook("before_asset_assign", [
    ["uuid", `v_row.${s("id")}`],
    ["text", "assign_asset.assignee_type"],
    ["text", "assign_asset.assignee_id"],
  ])}
  ${releaseOpen(`v_row.${s("id")}`)}
  insert into ${assignments} (${g("tenant")}, ${g("asset")}, ${g("assigneeType")}, ${g("assigneeId")}, ${g("note")}, ${g("assignedBy")})
  values (v_row.${s("tenant")}, v_row.${s("id")}, assign_asset.assignee_type, assign_asset.assignee_id, nullif(trim(assign_asset.note), ''), auth.uid());
  update ${assets} x set ${s("assigneeType")} = assign_asset.assignee_type, ${s("assigneeId")} = assign_asset.assignee_id, ${s("updatedAt")} = now()
    where x.${s("id")} = v_row.${s("id")}
    returning * into v_row;
  ${assetRecord("asset.assigned", "v_row", "assigned asset")}
  ${ctx.hook("after_asset_assign", [["uuid", `v_row.${s("id")}`]])}
  return ${assetJson("v_row")};
end;
$$;
${userGrant(`${fn("assign_asset")}(uuid, text, text, text)`)}

-- Ends the asset's current assignment; a no-op when it has none.
create or replace function ${fn("release_asset")}(asset_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${assets}%rowtype;
begin
  select * into v_row from ${assets} x where x.${s("id")} = release_asset.asset_id for update;
  if not found or not ${readsAsset("v_row")} then
    ${assetMissing}
  end if;
  if not ${allowed(`v_row.${s("tenant")}`, assign)} then
    ${forbidden("not allowed to assign assets")}
  end if;
  if v_row.${s("assigneeType")} is not null then
    ${releaseOpen(`v_row.${s("id")}`)}
    update ${assets} x set ${s("assigneeType")} = null, ${s("assigneeId")} = null, ${s("updatedAt")} = now()
      where x.${s("id")} = v_row.${s("id")}
      returning * into v_row;
    ${assetRecord("asset.released", "v_row", "released asset")}
  end if;
  return ${assetJson("v_row")};
end;
$$;
${userGrant(`${fn("release_asset")}(uuid)`)}

-- An asset with its location's path and the booking resources and open work
-- items that name it.
create or replace function ${fn("get_asset")}(asset_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${assets}%rowtype;
begin
  select * into v_row from ${assets} x where x.${s("id")} = get_asset.asset_id;
  if not found or not ${readsAsset("v_row")} then
    ${assetMissing}
  end if;
  return ${assetJson("v_row")} || jsonb_build_object(
    'locationPath', case when v_row.${s("location")} is null then '[]'::jsonb else ${pathOf(`v_row.${s("location")}`)} end,
    'links', ${links(`v_row.${s("id")}`)});
end;
$$;
${userGrant(`${fn("get_asset")}(uuid)`)}

-- Assets newest first. With location_id, include_sublocations also returns
-- the assets below it. With tenant null an assignee decides the organization.
create or replace function ${fn("list_assets")}(tenant ${idType}, location_id uuid default null, include_sublocations boolean default false, kind text default null, status text default null, assignee_type text default null, assignee_id text default null, query text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with recursive below as (
    select y.${l("id")} as id, 0 as depth from ${locations} y where y.${l("id")} = list_assets.location_id
    union all
    select y.${l("id")}, below.depth + 1 from ${locations} y join below on y.${l("parent")} = below.id
    where coalesce(list_assets.include_sublocations, false) and below.depth < 64
  )
  select coalesce(jsonb_agg(z.item order by z.created_at desc, z.id), '[]'::jsonb)
  from (
    select ${assetJson("x")} as item, x.${s("createdAt")} as created_at, x.${s("id")} as id
    from ${assets} x
    where (list_assets.tenant is null or x.${s("tenant")} = list_assets.tenant)
      and (list_assets.location_id is null or x.${s("location")} in (select below.id from below))
      and (list_assets.kind is null or x.${s("kind")} = list_assets.kind)
      and (list_assets.status is null or x.${s("status")} = list_assets.status)
      and (list_assets.assignee_type is null or x.${s("assigneeType")} = list_assets.assignee_type)
      and (list_assets.assignee_id is null or x.${s("assigneeId")} = list_assets.assignee_id)
      and (list_assets.query is null or x.${s("name")} ilike '%' || list_assets.query || '%' or x.${s("tag")} = list_assets.query or x.${s("serial")} = list_assets.query)
      and (list_assets.before is null or x.${s("createdAt")} < list_assets.before)
      and ${readsAsset("x")}
    order by x.${s("createdAt")} desc, x.${s("id")}
    limit ${pageSize("list_assets.page_size", 50, 500)}
  ) z
$$;
${userGrant(`${fn("list_assets")}(${listArgs})`)}

-- An asset's assignments, newest first.
create or replace function ${fn("asset_assignment_history")}(asset_id uuid, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${assets}%rowtype;
begin
  select * into v_row from ${assets} x where x.${s("id")} = asset_assignment_history.asset_id;
  if not found or not ${readsAsset("v_row")} then
    ${assetMissing}
  end if;
  return coalesce((
    select jsonb_agg(z.item order by z.assigned_at desc, z.id)
    from (
      select ${assignmentJson("y")} as item, y.${g("assignedAt")} as assigned_at, y.${g("id")} as id
      from ${assignments} y where y.${g("asset")} = v_row.${s("id")}
      order by y.${g("assignedAt")} desc, y.${g("id")}
      limit ${pageSize("asset_assignment_history.page_size", 50, 500)}
    ) z
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("asset_assignment_history")}(uuid, integer)`)}

-- The assets and locations within radius_meters of a point, nearest first,
-- each with distanceMeters. ${postgis ? "PostGIS geography (ST_DWithin)." : "The haversine distance on latitude and longitude."}
create or replace function ${fn("assets_near")}(tenant ${idType}, latitude double precision, longitude double precision, radius_meters double precision, kind text default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  ${postgis ? `v_point extensions.geography := ${geographyPoint("assets_near.latitude", "assets_near.longitude")};` : `v_dlat double precision := assets_near.radius_meters / 111320.0;\n  v_dlng double precision := assets_near.radius_meters / (111320.0 * greatest(cos(radians(assets_near.latitude)), 0.01));`}
  v_limit integer := ${pageSize("assets_near.page_size", 50, 500)};
begin
  if not ${allowed("assets_near.tenant", read)} then
    ${forbidden("not allowed to read assets")}
  end if;
  if assets_near.latitude is null or assets_near.longitude is null or assets_near.latitude not between -90 and 90 or assets_near.longitude not between -180 and 180 then
    ${invalid("ASSETS_POINT_INVALID", "latitude must be between -90 and 90 and longitude between -180 and 180")}
  end if;
  if assets_near.radius_meters is null or assets_near.radius_meters <= 0 or assets_near.radius_meters > 1000000 then
    ${invalid("ASSETS_RADIUS_INVALID", "radius_meters must be above 0 and at most 1000000")}
  end if;
  return jsonb_build_object(
    'assets', coalesce((
      select jsonb_agg(z.item || jsonb_build_object('distanceMeters', z.distance) order by z.distance, z.id)
      from (
        select ${assetJson("x")} as item, ${distance("x", "assets")} as distance, x.${s("id")} as id
        from ${assets} x
        where x.${s("tenant")} = assets_near.tenant and x.${s("latitude")} is not null and x.${s("status")} <> 'retired'
          and (assets_near.kind is null or x.${s("kind")} = assets_near.kind)
          and ${near("x", "assets")}
        order by 2, 3
        limit v_limit
      ) z
    ), '[]'::jsonb),
    'locations', coalesce((
      select jsonb_agg(z.item || jsonb_build_object('distanceMeters', z.distance) order by z.distance, z.id)
      from (
        select ${locationJson("x")} as item, ${distance("x", "locations")} as distance, x.${l("id")} as id
        from ${locations} x
        where x.${l("tenant")} = assets_near.tenant and x.${l("latitude")} is not null and x.${l("archivedAt")} is null
          and ${near("x", "locations")}
        order by 2, 3
        limit v_limit
      ) z
    ), '[]'::jsonb));
end;
$$;
${userGrant(`${fn("assets_near")}(${idType}, double precision, double precision, double precision, text, integer)`)}

-- The locations whose area contains a point, smallest area first. Needs the
-- postgis option.
create or replace function ${fn("asset_locations_at")}(tenant ${idType}, latitude double precision, longitude double precision)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${allowed("asset_locations_at.tenant", read)} then
    ${forbidden("not allowed to read assets")}
  end if;
  ${
    postgis
      ? `return coalesce((
    select jsonb_agg(z.item order by z.size, z.id)
    from (
      select ${locationJson("x")} as item, extensions.st_area(x.area) as size, x.${l("id")} as id
      from ${locations} x
      where x.${l("tenant")} = asset_locations_at.tenant and x.${l("archivedAt")} is null and x.area is not null
        and extensions.st_covers(x.area, ${geographyPoint("asset_locations_at.latitude", "asset_locations_at.longitude")})
    ) z
  ), '[]'::jsonb);`
      : needsPostgis
  }
end;
$$;
${userGrant(`${fn("asset_locations_at")}(${idType}, double precision, double precision)`)}

-- Names the asset a booking resource or a work item is about; a null
-- asset_id clears it. target_type is booking_resource or work_item.
create or replace function ${fn("set_asset_link")}(target_type text, target_id uuid, asset_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${idType};
begin
  ${
    linkTargets.length === 0
      ? invalid(
          "ASSETS_LINK_UNSUPPORTED",
          "install bookings or tasks to link assets",
        )
      : `case set_asset_link.target_type
  ${linkTargets.join("\n  ")}
  else
    ${invalid("ASSETS_LINK_UNSUPPORTED", "target_type must be booking_resource or work_item")}
  end case;
  if v_tenant is null then
    ${fail("ASSETS_LINK_TARGET_NOT_FOUND", "the record to link doesn't exist", "P0002")}
  end if;
  if not ${allowed("v_tenant", manage)} then
    ${forbidden("not allowed to manage assets")}
  end if;
  if set_asset_link.asset_id is not null and not exists (
    select 1 from ${assets} y where y.${s("id")} = set_asset_link.asset_id and y.${s("tenant")} = v_tenant
  ) then
    ${assetMissing}
  end if;
  ${linkWrites.join("\n  ")}
  return jsonb_build_object('targetType', set_asset_link.target_type, 'targetId', set_asset_link.target_id, 'assetId', set_asset_link.asset_id);`
  }
end;
$$;
${userGrant(`${fn("set_asset_link")}(text, uuid, uuid)`)}
`;
}
