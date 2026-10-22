import type { AssetsEvents } from "../../blocks/assets/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { fail, lockTable, triggerGrant, schemaPreamble } from "../shared.ts";
import { moduleOperations } from "./access-model.ts";
import {
  assetsFunctions,
  assetsPostgis,
  GEOGRAPHY,
  geographyPoint,
} from "./assets-functions.ts";

const LOCATION_PAYLOAD = [
  "organizationId",
  "id",
  "kind",
  "name",
  "parentId",
] as const;

const ASSET_PAYLOAD = [
  "organizationId",
  "id",
  "kind",
  "name",
  "status",
  "locationId",
  "assigneeType",
  "assigneeId",
] as const;

const EVENTS: BlockSqlEvents<AssetsEvents> = {
  "asset_location.created": {
    subject: "asset-locations",
    payload: LOCATION_PAYLOAD,
  },
  "asset_location.updated": {
    subject: "asset-locations",
    payload: LOCATION_PAYLOAD,
  },
  "asset_location.archived": {
    subject: "asset-locations",
    payload: LOCATION_PAYLOAD,
  },
  "asset.created": { subject: "assets", payload: ASSET_PAYLOAD },
  "asset.updated": { subject: "assets", payload: ASSET_PAYLOAD },
  "asset.assigned": { subject: "assets", payload: ASSET_PAYLOAD },
  "asset.released": { subject: "assets", payload: ASSET_PAYLOAD },
};

const NAMES: BlockSqlNames = {
  options: ["postgis"],
  entities: {
    asset: {
      table: "assets",
      singular: "asset",
      primary: true,
      subject: {
        title: "name",
        permissions: { read: "read", write: "manage" },
      },
    },
    asset_location: {
      table: "locations",
      singular: "asset_location",
      subject: {
        title: "name",
        permissions: { read: "read", write: "manage" },
      },
    },
  },
  events: EVENTS,
  hooks: ["before_asset_assign", "after_asset_assign"],
  tables: {
    locations: {
      name: "asset_locations",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        parent: "parent_id",
        kind: "kind",
        name: "name",
        code: "code",
        address: "address",
        latitude: "latitude",
        longitude: "longitude",
        metadata: "metadata",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    assets: {
      name: "assets",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        location: "location_id",
        kind: "kind",
        name: "name",
        tag: "tag",
        serial: "serial_number",
        status: "status",
        assigneeType: "assignee_type",
        assigneeId: "assignee_id",
        latitude: "latitude",
        longitude: "longitude",
        metadata: "metadata",
        retiredAt: "retired_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    assignments: {
      name: "asset_assignments",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        asset: "asset_id",
        assigneeType: "assignee_type",
        assigneeId: "assignee_id",
        note: "note",
        assignedBy: "assigned_by",
        assignedAt: "assigned_at",
        releasedAt: "released_at",
      },
    },
  },
};

/** A latitude and longitude pair, both set or both null. */
const coordinates = (latitude: string, longitude: string): string =>
  `${latitude} double precision check (${latitude} between -90 and 90),
  ${longitude} double precision check (${longitude} between -180 and 180),`;

const pointColumn = (latitude: string, longitude: string): string =>
  `point ${GEOGRAPHY}(Point, 4326) generated always as (case when ${latitude} is null then null else ${geographyPoint(latitude, longitude)} end) stored,`;

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const locations = ctx.table("locations");
  const assets = ctx.table("assets");
  const assignments = ctx.table("assignments");
  const l = (column: string): string => ctx.col("locations", column);
  const s = (column: string): string => ctx.col("assets", column);
  const g = (column: string): string => ctx.col("assignments", column);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("assets");
  const read = ctx.permission("read", permissions.read);
  const postgis = assetsPostgis(ctx);
  const idType = ctx.idType;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const policyName = (logical: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_read`);

  const links = [
    ctx.installed("bookings") && ctx.of("bookings").manages
      ? `alter table ${ctx.of("bookings").table("resources")} add column if not exists asset_id uuid references ${assets} (${s("id")}) on delete set null;
create index if not exists ${sqlIdent(`${ctx.of("bookings").tableName("resources").name}_asset_idx`)} on ${ctx.of("bookings").table("resources")} (asset_id) where asset_id is not null;`
      : "",
    ctx.installed("work-items") && ctx.of("work-items").manages
      ? `alter table ${ctx.of("work-items").table("items")} add column if not exists asset_id uuid references ${assets} (${s("id")}) on delete set null;
create index if not exists ${sqlIdent(`${ctx.of("work-items").tableName("items").name}_asset_idx`)} on ${ctx.of("work-items").table("items")} (asset_id) where asset_id is not null;`
      : "",
  ]
    .filter((part) => part !== "")
    .join("\n");

  const tables = ctx.manages
    ? `${postgis ? "create extension if not exists postgis with schema extensions;\n" : ""}create table if not exists ${locations} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${idType} not null,
  ${l("parent")} uuid references ${locations} (${l("id")}) on delete restrict,
  -- site, building, floor, unit, room, or the app's own kind.
  ${l("kind")} text not null check (${l("kind")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${l("name")} text not null check (length(${l("name")}) between 1 and 200),
  ${l("code")} text check (${l("code")} is null or length(${l("code")}) between 1 and 100),
  ${l("address")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${l("address")}) = 'object'),
  ${coordinates(l("latitude"), l("longitude"))}
  ${postgis ? `${pointColumn(l("latitude"), l("longitude"))}\n  -- A site's or unit's outline, from GeoJSON.\n  area ${GEOGRAPHY}(MultiPolygon, 4326),\n  ` : ""}${l("metadata")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${l("metadata")}) = 'object'),
  ${l("archivedAt")} timestamptz,
  ${l("createdAt")} timestamptz not null default now(),
  ${l("updatedAt")} timestamptz not null default now(),
  unique (${l("tenant")}, ${l("code")}),
  check ((${l("latitude")} is null) = (${l("longitude")} is null))
);
create index if not exists ${name("locations", "parent_idx")} on ${locations} (${l("parent")}, ${l("tenant")});
create index if not exists ${name("locations", "coordinates_idx")} on ${locations} (${l("tenant")}, ${l("latitude")}, ${l("longitude")}) where ${l("latitude")} is not null;
${postgis ? `create index if not exists ${name("locations", "point_idx")} on ${locations} using gist (point);\ncreate index if not exists ${name("locations", "area_idx")} on ${locations} using gist (area);\n` : ""}
create table if not exists ${assets} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${idType} not null,
  ${s("location")} uuid references ${locations} (${l("id")}) on delete set null,
  ${s("kind")} text not null check (${s("kind")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${s("name")} text not null check (length(${s("name")}) between 1 and 200),
  -- The asset tag, unique per organization.
  ${s("tag")} text check (${s("tag")} is null or length(${s("tag")}) between 1 and 100),
  ${s("serial")} text check (${s("serial")} is null or length(${s("serial")}) <= 200),
  ${s("status")} text not null default 'active' check (${s("status")} in ('active', 'maintenance', 'retired')),
  -- member (a user id) or a subject type such as party, with its id.
  ${s("assigneeType")} text check (${s("assigneeType")} is null or ${s("assigneeType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${s("assigneeId")} text,
  -- Where a moving asset (a vehicle) was last seen.
  ${coordinates(s("latitude"), s("longitude"))}
  ${postgis ? `${pointColumn(s("latitude"), s("longitude"))}\n  ` : ""}${s("metadata")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${s("metadata")}) = 'object'),
  ${s("retiredAt")} timestamptz,
  ${s("createdBy")} uuid,
  ${s("createdAt")} timestamptz not null default now(),
  ${s("updatedAt")} timestamptz not null default now(),
  unique (${s("tenant")}, ${s("tag")}),
  check ((${s("assigneeType")} is null) = (${s("assigneeId")} is null)),
  check ((${s("latitude")} is null) = (${s("longitude")} is null))
);
create index if not exists ${name("assets", "location_idx")} on ${assets} (${s("location")}, ${s("tenant")});
create index if not exists ${name("assets", "assignee_idx")} on ${assets} (${s("tenant")}, ${s("assigneeType")}, ${s("assigneeId")}) where ${s("assigneeType")} is not null;
create index if not exists ${name("assets", "kind_idx")} on ${assets} (${s("tenant")}, ${s("kind")}, ${s("status")});
create index if not exists ${name("assets", "coordinates_idx")} on ${assets} (${s("tenant")}, ${s("latitude")}, ${s("longitude")}) where ${s("latitude")} is not null;
${postgis ? `create index if not exists ${name("assets", "point_idx")} on ${assets} using gist (point);\n` : ""}
create table if not exists ${assignments} (
  ${g("id")} uuid primary key default gen_random_uuid(),
  ${g("tenant")} ${idType} not null,
  ${g("asset")} uuid not null references ${assets} (${s("id")}) on delete cascade,
  ${g("assigneeType")} text not null,
  ${g("assigneeId")} text not null,
  ${g("note")} text check (${g("note")} is null or length(${g("note")}) <= 2000),
  ${g("assignedBy")} uuid,
  ${g("assignedAt")} timestamptz not null default now(),
  ${g("releasedAt")} timestamptz
);
create unique index if not exists ${name("assignments", "open_idx")} on ${assignments} (${g("asset")}) where ${g("releasedAt")} is null;
create index if not exists ${name("assignments", "history_idx")} on ${assignments} (${g("asset")}, ${g("assignedAt")} desc);

${lockTable(locations, { read: true })}
drop policy if exists ${policyName("locations")} on ${locations};
create policy ${policyName("locations")} on ${locations} for select to authenticated
  using (${ctx.scope.check(l("tenant"), read)});
${lockTable(assets, { read: true })}
drop policy if exists ${policyName("assets")} on ${assets};
create policy ${policyName("assets")} on ${assets} for select to authenticated
  using (${ctx.scope.check(s("tenant"), read)}
    or (${s("assigneeType")} = 'member' and ${s("assigneeId")} = (select auth.uid())::text));
${lockTable(assignments, { read: true })}
drop policy if exists ${policyName("assignments")} on ${assignments};
create policy ${policyName("assignments")} on ${assignments} for select to authenticated
  using (${g("asset")} in (select y.${s("id")} from ${assets} y));

-- A location's parent is in the same organization and never one of its own
-- descendants, so the hierarchy stays a tree.
create or replace function ${fn("asset_location_check_parent")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.${l("parent")} is null then
    return new;
  end if;
  if not exists (
    select 1 from ${locations} x where x.${l("id")} = new.${l("parent")} and x.${l("tenant")} = new.${l("tenant")}
  ) then
    ${fail("ASSETS_LOCATION_NOT_FOUND", "the parent location doesn't exist in this organization", "P0002")}
  end if;
  if tg_op = 'UPDATE' and exists (
    with recursive up as (
      select x.${l("id")} as id, x.${l("parent")} as parent, 1 as depth from ${locations} x where x.${l("id")} = new.${l("parent")}
      union all
      select x.${l("id")}, x.${l("parent")}, up.depth + 1 from ${locations} x join up on x.${l("id")} = up.parent where up.depth < 64
    )
    select 1 from up where up.id = new.${l("id")}
  ) then
    ${fail("ASSETS_LOCATION_CYCLE", "a location can't be inside one of its own sublocations", "23514")}
  end if;
  return new;
end;
$$;
${triggerGrant(`${fn("asset_location_check_parent")}()`)}
drop trigger if exists ${ctx.trigger("asset_locations_parent")} on ${locations};
create trigger ${ctx.trigger("asset_locations_parent")} before insert or update of ${l("parent")} on ${locations}
  for each row execute function ${fn("asset_location_check_parent")}();
${links}
`
    : "";

  return `${schemaPreamble(ctx)}
${tables}
${assetsFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  const id = "{id}";

  return [
    {
      name: "list_assets",
      args: [
        id,
        "uuid",
        "boolean",
        "text",
        "text",
        "text",
        "text",
        "text",
        "timestamptz",
        "integer",
      ],
      returns: "jsonb",
    },
    { name: "get_asset", args: ["uuid"], returns: "jsonb" },
    {
      name: "assign_asset",
      args: ["uuid", "text", "text", "text"],
      returns: "jsonb",
    },
  ];
}

export const ASSETS: BlockSqlDefinition = {
  internal: ["asset_location_check_parent"],
  name: "assets",
  scopes: ["tenant"],
  title: "Assets and locations",
  description:
    "A location hierarchy (site, building, unit) and an asset registry with tags, status, coordinates and assignment to members or records. Optional PostGIS stores points and areas as geography; bookings resources and work items can name an asset.",
  requires: ["tenant", "access"],
  integrates: ["bookings", "work-items", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
