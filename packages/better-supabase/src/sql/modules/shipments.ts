import type { ShipmentsEvents } from "../../blocks/shipments/events.ts";
import type {
  ExtraColumn,
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import {
  LABEL_FORMATS,
  SHIPMENT_STATUSES,
  TRACKING_STATUSES,
} from "../../blocks/shipments/statuses.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  addForeignKey,
  extraFieldsArg,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";
import { subjectTenant } from "../subject-check-sql.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { moduleOperations } from "./access-model.ts";

/** The most packages one shipment holds. */
const MAX_PACKAGES = 50;

/** The most tracking events one call records. */
const MAX_EVENTS = 500;

const EVENTS: BlockSqlEvents<ShipmentsEvents> = {
  "shipment.created": {
    subject: "shipments",
    payload: ["organizationId", "id", "reference", "subjectType", "subjectId"],
  },
  "shipment.labeled": {
    subject: "shipments",
    payload: ["organizationId", "id", "carrier", "service", "trackingNumber"],
  },
  "shipment.status_changed": {
    subject: "shipments",
    payload: ["organizationId", "id", "from", "to", "trackingNumber"],
  },
  "shipment.cancelled": {
    subject: "shipments",
    payload: ["organizationId", "id", "trackingNumber"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    shipment: {
      table: "shipments",
      singular: "shipment",
      primary: true,
      subject: {
        title: "reference",
        permissions: { read: "read", write: "manage" },
      },
    },
    shipment_package: { table: "packages", singular: "shipment_package" },
    shipment_tracking_event: {
      table: "trackingEvents",
      singular: "shipment_tracking_event",
    },
  },
  events: EVENTS,
  options: ["extraColumns"],
  tables: {
    shipments: {
      name: "shipments",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        reference: "reference",
        status: "status",
        fromAddress: "from_address",
        toAddress: "to_address",
        fromLocation: "from_location_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        carrier: "carrier",
        service: "service",
        trackingNumber: "tracking_number",
        trackingUrl: "tracking_url",
        labelId: "label_id",
        labelUrl: "label_url",
        labelFormat: "label_format",
        labelCost: "label_cost",
        currency: "currency",
        labeledAt: "labeled_at",
        deliveredAt: "delivered_at",
        cancelledAt: "cancelled_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    packages: {
      name: "shipment_packages",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        shipment: "shipment_id",
        position: "position",
        weight: "weight_grams",
        length: "length_mm",
        width: "width_mm",
        height: "height_mm",
        reference: "reference",
      },
    },
    trackingEvents: {
      name: "shipment_tracking_events",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        shipment: "shipment_id",
        externalId: "external_id",
        status: "status",
        occurredAt: "occurred_at",
        description: "description",
        location: "location",
        source: "source",
        createdAt: "created_at",
      },
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => sqlString(value)).join(", ");

const assetsOf = (ctx: BlockSqlContext): BlockSqlContext | undefined =>
  ctx.installed("assets") ? ctx.of("assets") : undefined;

// An address object with a street line, a city and a two-letter country.
const addressValid = (value: string): string =>
  `(jsonb_typeof(${value}) = 'object' and coalesce(${value} ->> 'country', '') ~ '^[A-Z]{2}$' and length(btrim(coalesce(${value} ->> 'line1', ''))) >= 1 and length(btrim(coalesce(${value} ->> 'city', ''))) >= 1 and length(${value}::text) <= 4000)`;

function tables(ctx: BlockSqlContext, extras: readonly ExtraColumn[]): string {
  if (!ctx.manages) {
    return "";
  }

  const shipments = ctx.table("shipments");
  const packages = ctx.table("packages");
  const events = ctx.table("trackingEvents");
  const h = (column: string): string => ctx.col("shipments", column);
  const p = (column: string): string => ctx.col("packages", column);
  const e = (column: string): string => ctx.col("trackingEvents", column);
  const assets = assetsOf(ctx);
  const read = ctx.permission("read", moduleOperations("shipments").read);
  const readable = (tenant: string): string => ctx.scope.check(tenant, read);

  const index = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const size = (column: string): string =>
    `${column} integer check (${column} is null or ${column} > 0)`;

  const locationKey =
    assets === undefined
      ? ""
      : `\n${addForeignKey({
          table: shipments,
          name: `${ctx.tableName("shipments").name}_from_location_fkey`,
          column: h("fromLocation"),
          references: `${assets.table("locations")} (${assets.col("locations", "id")})`,
          onDelete: "set null",
        })}`;

  return `
-- Shipments: packages going from one address to another, labeled through a
-- carrier, with a status that follows the latest tracking event.
create table if not exists ${shipments} (
  ${h("id")} uuid primary key default gen_random_uuid(),
  ${h("tenant")} ${ctx.idType} not null,
  ${h("reference")} text not null check (length(${h("reference")}) >= 1 and length(${h("reference")}) <= 100),
  ${h("status")} text not null default 'draft' check (${h("status")} in (${list(SHIPMENT_STATUSES)})),
  ${h("fromAddress")} jsonb not null check ${addressValid(h("fromAddress"))},
  ${h("toAddress")} jsonb not null check ${addressValid(h("toAddress"))},
  ${h("fromLocation")} uuid,
  ${h("subjectType")} text check (${h("subjectType")} is null or ${h("subjectType")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${h("subjectId")} text check (${h("subjectId")} is null or length(${h("subjectId")}) >= 1 and length(${h("subjectId")}) <= 200),
  ${h("carrier")} text check (${h("carrier")} is null or length(${h("carrier")}) >= 1 and length(${h("carrier")}) <= 100),
  ${h("service")} text check (${h("service")} is null or length(${h("service")}) >= 1 and length(${h("service")}) <= 100),
  ${h("trackingNumber")} text check (${h("trackingNumber")} is null or length(${h("trackingNumber")}) >= 1 and length(${h("trackingNumber")}) <= 100),
  ${h("trackingUrl")} text check (${h("trackingUrl")} is null or ${h("trackingUrl")} ~ '^https://' and length(${h("trackingUrl")}) <= 2000),
  ${h("labelId")} text check (${h("labelId")} is null or length(${h("labelId")}) >= 1 and length(${h("labelId")}) <= 200),
  ${h("labelUrl")} text check (${h("labelUrl")} is null or ${h("labelUrl")} ~ '^https://' and length(${h("labelUrl")}) <= 2000),
  ${h("labelFormat")} text check (${h("labelFormat")} is null or ${h("labelFormat")} in (${list(LABEL_FORMATS)})),
  ${h("labelCost")} bigint check (${h("labelCost")} is null or ${h("labelCost")} >= 0),
  ${h("currency")} text check (${h("currency")} is null or ${h("currency")} ~ '^[A-Z]{3}$'),
  ${h("labeledAt")} timestamptz,
  ${h("deliveredAt")} timestamptz,
  ${h("cancelledAt")} timestamptz,
  ${h("createdBy")} uuid,
  ${h("createdAt")} timestamptz not null default now(),
  ${h("updatedAt")} timestamptz not null default now(),
  check ((${h("subjectType")} is null) = (${h("subjectId")} is null)),
  check ((${h("labelCost")} is null) = (${h("currency")} is null)),
  check (${h("status")} in ('draft', 'cancelled') or (${h("carrier")} is not null and ${h("trackingNumber")} is not null))
);${addExtraColumns(shipments, extras)}
create index if not exists ${index("shipments", "tenant_idx")} on ${shipments} (${h("tenant")}, ${h("createdAt")} desc);
create index if not exists ${index("shipments", "status_idx")} on ${shipments} (${h("tenant")}, ${h("status")});
create unique index if not exists ${index("shipments", "tracking_key")} on ${shipments} (${h("carrier")}, ${h("trackingNumber")}) where ${h("trackingNumber")} is not null;
create index if not exists ${index("shipments", "subject_idx")} on ${shipments} (${h("tenant")}, ${h("subjectType")}, ${h("subjectId")});
create index if not exists ${index("shipments", "location_idx")} on ${shipments} (${h("fromLocation")});
${lockTable(shipments, { read: true })}
drop policy if exists ${index("shipments", "read")} on ${shipments};
create policy ${index("shipments", "read")} on ${shipments} for select to authenticated
  using (${readable(h("tenant"))});
create table if not exists ${packages} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("shipment")} uuid not null references ${shipments} (${h("id")}) on delete cascade,
  ${p("position")} integer not null check (${p("position")} >= 1),
  ${p("weight")} integer not null check (${p("weight")} > 0),
  ${size(p("length"))},
  ${size(p("width"))},
  ${size(p("height"))},
  ${p("reference")} text check (${p("reference")} is null or length(${p("reference")}) <= 100),
  unique (${p("shipment")}, ${p("position")})
);
${lockTable(packages, { read: true })}
drop policy if exists ${index("packages", "read")} on ${packages};
create policy ${index("packages", "read")} on ${packages} for select to authenticated
  using (${readable(p("tenant"))});
-- The tracking timeline. A carrier event id is recorded once per shipment, so
-- a redelivered webhook or a repeated poll changes nothing.
create table if not exists ${events} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("shipment")} uuid not null references ${shipments} (${h("id")}) on delete cascade,
  ${e("externalId")} text not null check (length(${e("externalId")}) >= 1 and length(${e("externalId")}) <= 200),
  ${e("status")} text not null check (${e("status")} in (${list(TRACKING_STATUSES)})),
  ${e("occurredAt")} timestamptz not null,
  ${e("description")} text check (${e("description")} is null or length(${e("description")}) <= 1000),
  ${e("location")} text check (${e("location")} is null or length(${e("location")}) <= 200),
  ${e("source")} text not null check (${e("source")} in ('carrier', 'webhook', 'manual')),
  ${e("createdAt")} timestamptz not null default now(),
  unique (${e("shipment")}, ${e("externalId")})
);
create index if not exists ${index("trackingEvents", "timeline_idx")} on ${events} (${e("shipment")}, ${e("occurredAt")});
${lockTable(events, { read: true })}
drop policy if exists ${index("trackingEvents", "read")} on ${events};
create policy ${index("trackingEvents", "read")} on ${events} for select to authenticated
  using (${readable(e("tenant"))});${locationKey}
`;
}

function functions(
  ctx: BlockSqlContext,
  extras: readonly ExtraColumn[],
): string {
  const shipments = ctx.table("shipments");
  const packages = ctx.table("packages");
  const events = ctx.table("trackingEvents");
  const h = (column: string): string => ctx.col("shipments", column);
  const p = (column: string): string => ctx.col("packages", column);
  const e = (column: string): string => ctx.col("trackingEvents", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const keys = moduleOperations("shipments");
  const read = ctx.permission("read", keys.read);
  const manage = ctx.permission("manage", keys.manage);
  const assets = assetsOf(ctx);
  const fields = extraFieldsArg(extras);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const packagesJson = (row: string): string =>
    `(select coalesce(jsonb_agg(jsonb_build_object('id', pk.${p("id")}, 'position', pk.${p("position")}, 'weightGrams', pk.${p("weight")}, 'lengthMm', pk.${p("length")}, 'widthMm', pk.${p("width")}, 'heightMm', pk.${p("height")}, 'reference', pk.${p("reference")}) order by pk.${p("position")}), '[]'::jsonb) from ${packages} pk where pk.${p("shipment")} = ${row}.${h("id")})`;

  const shipmentJson = (row: string): string =>
    withExtraFields(
      `jsonb_build_object('id', ${row}.${h("id")}, 'organizationId', ${row}.${h("tenant")}::text, 'reference', ${row}.${h("reference")}, 'status', ${row}.${h("status")}, 'from', ${row}.${h("fromAddress")}, 'to', ${row}.${h("toAddress")}, 'fromLocationId', ${row}.${h("fromLocation")}, 'subjectType', ${row}.${h("subjectType")}, 'subjectId', ${row}.${h("subjectId")}, 'carrier', ${row}.${h("carrier")}, 'service', ${row}.${h("service")}, 'trackingNumber', ${row}.${h("trackingNumber")}, 'trackingUrl', ${row}.${h("trackingUrl")}, 'labelId', ${row}.${h("labelId")}, 'labelUrl', ${row}.${h("labelUrl")}, 'labelFormat', ${row}.${h("labelFormat")}, 'labelCost', ${row}.${h("labelCost")}::text, 'currency', ${row}.${h("currency")}, 'labeledAt', ${row}.${h("labeledAt")}, 'deliveredAt', ${row}.${h("deliveredAt")}, 'cancelledAt', ${row}.${h("cancelledAt")}, 'createdBy', ${row}.${h("createdBy")}, 'createdAt', ${row}.${h("createdAt")}, 'updatedAt', ${row}.${h("updatedAt")}, 'packages', ${packagesJson(row)})`,
      row,
      extras,
    );

  const eventJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${e("id")}, 'externalId', ${row}.${e("externalId")}, 'status', ${row}.${e("status")}, 'occurredAt', ${row}.${e("occurredAt")}, 'description', ${row}.${e("description")}, 'location', ${row}.${e("location")}, 'source', ${row}.${e("source")}, 'createdAt', ${row}.${e("createdAt")})`;

  const subject = (row: string): string =>
    `'shipments/' || ${row}.${h("id")}::text`;

  const base = (row: string): string =>
    `'organizationId', ${row}.${h("tenant")}::text, 'id', ${row}.${h("id")}`;

  const audited = (row: string, summary: string) => ({
    category: "data" as const,
    targetType: "shipment",
    recordId: `${row}.${h("id")}::text`,
    targetLabel: `${row}.${h("reference")}`,
    summary: sqlString(summary),
  });

  // Records the events in the jsonb array `input` on v_ship, skipping ids the
  // shipment already has, and counts the new ones into v_count.
  const insertEvents = (
    input: string,
    source: string,
  ): string => `  if jsonb_typeof(${input}) is distinct from 'array' or jsonb_array_length(${input}) > ${MAX_EVENTS} then
    ${fail("SHIPMENT_TRACKING_INVALID", `pass the tracking events as an array of at most ${MAX_EVENTS}`, "22023")}
  end if;
  begin
    with inserted as (
      insert into ${events} (${e("tenant")}, ${e("shipment")}, ${e("externalId")}, ${e("status")}, ${e("occurredAt")}, ${e("description")}, ${e("location")}, ${e("source")})
      select v_ship.${h("tenant")}, v_ship.${h("id")}, i ->> 'id', i ->> 'status', (i ->> 'occurredAt')::timestamptz, nullif(i ->> 'description', ''), nullif(i ->> 'location', ''), ${source}
      from jsonb_array_elements(${input}) i
      on conflict (${e("shipment")}, ${e("externalId")}) do nothing
      returning 1
    )
    select count(*)::integer into v_count from inserted;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    ${fail("SHIPMENT_TRACKING_INVALID", "each tracking event needs an id, a known status and an ISO 8601 occurredAt", "22023")}
  end;`;

  const statusRecord = ctx.record({
    type: "shipment.status_changed",
    payload: `jsonb_build_object(${base("v_ship")}, 'from', v_from, 'to', v_ship.${h("status")}, 'trackingNumber', v_ship.${h("trackingNumber")})`,
    subject: subject("v_ship"),
    tenant: `v_ship.${h("tenant")}`,
    audit: false,
  });

  // Moves v_ship to the status of its latest tracking event, unless it was
  // cancelled. Ties on the time go to the later stage.
  const syncStatus = `  select t.${e("status")}, t.${e("occurredAt")} into v_status, v_at
    from ${events} t
    where t.${e("shipment")} = v_ship.${h("id")}
    order by t.${e("occurredAt")} desc, array_position(array[${list(TRACKING_STATUSES)}]::text[], t.${e("status")}) desc
    limit 1;
  if v_status is not null and v_ship.${h("status")} <> 'cancelled' and v_status <> v_ship.${h("status")} then
    v_from := v_ship.${h("status")};
    update ${shipments} x set
      ${h("status")} = v_status,
      ${h("deliveredAt")} = case when v_status = 'delivered' then v_at end,
      ${h("updatedAt")} = now()
    where x.${h("id")} = v_ship.${h("id")}
    returning * into v_ship;
    ${statusRecord}
  end if;`;

  const syncDeclare = `
  v_count integer;
  v_status text;
  v_at timestamptz;
  v_from text;`;

  const locationCheck =
    assets === undefined
      ? `  if create_shipment.from_location_id is not null then
    ${fail("SHIPMENT_ASSETS_MISSING", "install the assets block to ship from one of its locations", "22023")}
  end if;`
      : `  if create_shipment.from_location_id is not null and not exists (
    select 1 from ${assets.table("locations")} l
    where l.${assets.col("locations", "id")} = create_shipment.from_location_id and l.${assets.col("locations", "tenant")} = create_shipment.tenant
  ) then
    ${fail("SHIPMENT_LOCATION_NOT_FOUND", "the location does not exist in this organization", "P0002")}
  end if;`;

  const createDrop = fields.drop(
    fn("create_shipment"),
    `${idType}, jsonb, jsonb, jsonb, text, uuid, text, text`,
  );

  const findForWrite = (
    arg: string,
  ): string => `  select * into v_ship from ${shipments} x where x.${h("id")} = ${arg} for update;
  if not found or not ${allowed(`v_ship.${h("tenant")}`, manage)} then
    ${fail("SHIPMENT_NOT_FOUND", "shipment not found", "P0002")}
  end if;`;

  return `
${createDrop}
-- Creates a draft shipment in tenant from from_address to to_address with its
-- packages: a jsonb array of { weightGrams, lengthMm?, widthMm?, heightMm?,
-- reference? }. reference defaults to a generated code.
create or replace function ${fn("create_shipment")}(tenant ${idType}, from_address jsonb, to_address jsonb, packages jsonb, reference text default null, from_location_id uuid default null, subject_type text default null, subject_id text default null${fields.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship ${shipments}%rowtype;
begin
  if not ${allowed("create_shipment.tenant", manage)} then
    ${fail("SHIPMENT_FORBIDDEN", "not allowed to manage shipments")}
  end if;
  if not coalesce(${addressValid("create_shipment.from_address")} and ${addressValid("create_shipment.to_address")}, false) then
    ${fail("SHIPMENT_ADDRESS_INVALID", "each address needs line1, city and a two-letter country", "22023")}
  end if;
  if jsonb_typeof(create_shipment.packages) is distinct from 'array'
    or jsonb_array_length(create_shipment.packages) < 1
    or jsonb_array_length(create_shipment.packages) > ${MAX_PACKAGES} then
    ${fail("SHIPMENT_EMPTY", `a shipment holds 1 to ${MAX_PACKAGES} packages`, "22023")}
  end if;
  if (create_shipment.subject_type is null) <> (create_shipment.subject_id is null) then
    ${fail("SHIPMENT_SUBJECT_INVALID", "pass both subject_type and subject_id, or neither", "22023")}
  end if;
  if create_shipment.subject_type is not null
    and ${subjectTenant(ctx, "create_shipment.subject_type", "create_shipment.subject_id")} is distinct from create_shipment.tenant::text then
    ${fail("SHIPMENT_SUBJECT_NOT_FOUND", "the record does not exist in this organization", "P0002")}
  end if;
${locationCheck}
  begin
    insert into ${shipments} (${h("tenant")}, ${h("reference")}, ${h("fromAddress")}, ${h("toAddress")}, ${h("fromLocation")}, ${h("subjectType")}, ${h("subjectId")}, ${h("createdBy")})
    values (create_shipment.tenant,
      coalesce(nullif(btrim(create_shipment.reference), ''), 'SHP-' || upper(substr(md5(gen_random_uuid()::text), 1, 10))),
      create_shipment.from_address, create_shipment.to_address, create_shipment.from_location_id,
      create_shipment.subject_type, create_shipment.subject_id, auth.uid())
    returning * into v_ship;
  exception when check_violation then
    ${fail("SHIPMENT_INVALID", "a shipment reference has 1 to 100 characters", "22023")}
  end;
  begin
    insert into ${packages} (${p("tenant")}, ${p("shipment")}, ${p("position")}, ${p("weight")}, ${p("length")}, ${p("width")}, ${p("height")}, ${p("reference")})
    select v_ship.${h("tenant")}, v_ship.${h("id")}, k.position,
      (k.item ->> 'weightGrams')::integer, (k.item ->> 'lengthMm')::integer, (k.item ->> 'widthMm')::integer, (k.item ->> 'heightMm')::integer,
      nullif(k.item ->> 'reference', '')
    from jsonb_array_elements(create_shipment.packages) with ordinality as k(item, position);
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    ${fail("SHIPMENT_PACKAGE_INVALID", "each package needs a weightGrams and sizes in whole millimeters above zero", "22023")}
  end;${writeExtraColumns(shipments, extras, "create_shipment.fields", `x.${h("id")} = v_ship.${h("id")}`, "v_ship")}
  ${ctx.record({
    type: "shipment.created",
    payload: `jsonb_build_object(${base("v_ship")}, 'reference', v_ship.${h("reference")}, 'subjectType', v_ship.${h("subjectType")}, 'subjectId', v_ship.${h("subjectId")})`,
    subject: subject("v_ship"),
    tenant: `v_ship.${h("tenant")}`,
    audit: audited("v_ship", "created shipment"),
  })}
  return ${shipmentJson("v_ship")};
end;
$$;
${userGrant(`${fn("create_shipment")}(${idType}, jsonb, jsonb, jsonb, text, uuid, text, text${fields.type})`)}

-- One shipment with its packages and label, or null.
create or replace function ${fn("get_shipment")}(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship ${shipments}%rowtype;
begin
  select * into v_ship from ${shipments} x where x.${h("id")} = get_shipment.shipment_id;
  if not found or not ${allowed(`v_ship.${h("tenant")}`, read)} then
    return null;
  end if;
  return ${shipmentJson("v_ship")};
end;
$$;
${userGrant(`${fn("get_shipment")}(uuid)`)}

-- A tenant's shipments, newest first, filtered by status, record or carrier.
create or replace function ${fn("list_shipments")}(tenant ${idType}, status text default null, subject_type text default null, subject_id text default null, carrier text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${allowed("list_shipments.tenant", read)} then
    ${fail("SHIPMENT_FORBIDDEN", "not allowed to read shipments")}
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select ${shipmentJson("x")} as item, x.${h("createdAt")} as created, x.${h("id")} as id
      from ${shipments} x
      where x.${h("tenant")} = list_shipments.tenant
        and (list_shipments.status is null or x.${h("status")} = list_shipments.status)
        and (list_shipments.subject_type is null or (x.${h("subjectType")} = list_shipments.subject_type and x.${h("subjectId")} = list_shipments.subject_id))
        and (list_shipments.carrier is null or x.${h("carrier")} = list_shipments.carrier)
        and (list_shipments.before is null or x.${h("createdAt")} < list_shipments.before)
      order by x.${h("createdAt")} desc, x.${h("id")} desc
      limit ${pageSize("list_shipments.page_size", 50, 500)}
    ) z
  );
end;
$$;
${userGrant(`${fn("list_shipments")}(${idType}, text, text, text, text, timestamptz, integer)`)}

-- Stores the label a carrier sold for a draft shipment and starts its
-- timeline with a label_created event.
create or replace function ${fn("set_shipment_label")}(shipment_id uuid, carrier text, service text, tracking_number text, label_id text, label_cost bigint, currency text, label_format text default 'pdf', label_url text default null, tracking_url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship ${shipments}%rowtype;${syncDeclare}
begin
${findForWrite("set_shipment_label.shipment_id")}
  if v_ship.${h("status")} <> 'draft' then
    ${fail("SHIPMENT_NOT_DRAFT", "only a draft shipment gets a label", "55000")}
  end if;
  begin
    update ${shipments} x set
      ${h("carrier")} = set_shipment_label.carrier,
      ${h("service")} = set_shipment_label.service,
      ${h("trackingNumber")} = set_shipment_label.tracking_number,
      ${h("trackingUrl")} = set_shipment_label.tracking_url,
      ${h("labelId")} = set_shipment_label.label_id,
      ${h("labelUrl")} = set_shipment_label.label_url,
      ${h("labelFormat")} = coalesce(set_shipment_label.label_format, 'pdf'),
      ${h("labelCost")} = set_shipment_label.label_cost,
      ${h("currency")} = set_shipment_label.currency,
      ${h("labeledAt")} = now(),
      ${h("updatedAt")} = now()
    where x.${h("id")} = v_ship.${h("id")}
    returning * into v_ship;
  exception
    when unique_violation then
      ${fail("SHIPMENT_TRACKING_TAKEN", "another shipment has this carrier and tracking number", "23505")}
    when check_violation or not_null_violation then
      ${fail("SHIPMENT_LABEL_INVALID", "a label needs a carrier, service, tracking number, label id, a cost of zero or more and a currency", "22023")}
  end;
  if v_ship.${h("carrier")} is null or v_ship.${h("service")} is null or v_ship.${h("trackingNumber")} is null or v_ship.${h("labelId")} is null or v_ship.${h("labelCost")} is null then
    ${fail("SHIPMENT_LABEL_INVALID", "a label needs a carrier, service, tracking number, label id, a cost of zero or more and a currency", "22023")}
  end if;
  insert into ${events} (${e("tenant")}, ${e("shipment")}, ${e("externalId")}, ${e("status")}, ${e("occurredAt")}, ${e("description")}, ${e("source")})
  values (v_ship.${h("tenant")}, v_ship.${h("id")}, 'label:' || v_ship.${h("labelId")}, 'label_created', now(), 'Label created', 'carrier')
  on conflict (${e("shipment")}, ${e("externalId")}) do nothing;
  ${ctx.record({
    type: "shipment.labeled",
    payload: `jsonb_build_object(${base("v_ship")}, 'carrier', v_ship.${h("carrier")}, 'service', v_ship.${h("service")}, 'trackingNumber', v_ship.${h("trackingNumber")})`,
    subject: subject("v_ship"),
    tenant: `v_ship.${h("tenant")}`,
    audit: audited("v_ship", "bought shipping label"),
  })}
${syncStatus}
  return ${shipmentJson("v_ship")};
end;
$$;
${userGrant(`${fn("set_shipment_label")}(uuid, text, text, text, text, bigint, text, text, text, text)`)}

-- Records tracking events on a labeled shipment: a jsonb array of { id,
-- status, occurredAt, description?, location? }. Ids it already has are
-- skipped; the status follows the latest event.
create or replace function ${fn("record_tracking_events")}(shipment_id uuid, events jsonb, source text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship ${shipments}%rowtype;${syncDeclare}
begin
${findForWrite("record_tracking_events.shipment_id")}
  if v_ship.${h("trackingNumber")} is null then
    ${fail("SHIPMENT_NOT_LABELED", "a shipment gets tracking events once it has a label", "55000")}
  end if;
  if record_tracking_events.source is null or record_tracking_events.source not in ('carrier', 'manual') then
    ${fail("SHIPMENT_TRACKING_INVALID", "the source is carrier or manual", "22023")}
  end if;
${insertEvents("record_tracking_events.events", "record_tracking_events.source")}
${syncStatus}
  return jsonb_build_object('recorded', v_count, 'shipment', ${shipmentJson("v_ship")});
end;
$$;
${userGrant(`${fn("record_tracking_events")}(uuid, jsonb, text)`)}

-- Records a carrier webhook's tracking events on the shipment with that
-- carrier and tracking number. Service role only: the webhook route verifies
-- the signature first. Null when no shipment has the tracking number.
create or replace function ${fn("ingest_tracking_events")}(carrier text, tracking_number text, events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship ${shipments}%rowtype;${syncDeclare}
begin
  select * into v_ship from ${shipments} x
    where x.${h("carrier")} = ingest_tracking_events.carrier
      and x.${h("trackingNumber")} = ingest_tracking_events.tracking_number
    for update;
  if not found then
    return null;
  end if;
${insertEvents("ingest_tracking_events.events", "'webhook'")}
${syncStatus}
  return jsonb_build_object('id', v_ship.${h("id")}, 'organizationId', v_ship.${h("tenant")}::text, 'status', v_ship.${h("status")}, 'recorded', v_count);
end;
$$;
${serviceGrant(`${fn("ingest_tracking_events")}(text, text, jsonb)`)}

-- Cancels a shipment that hasn't shipped: a draft, or one whose label the
-- carrier voided.
create or replace function ${fn("cancel_shipment")}(shipment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship ${shipments}%rowtype;
begin
${findForWrite("cancel_shipment.shipment_id")}
  if v_ship.${h("status")} not in ('draft', 'label_created') then
    ${fail("SHIPMENT_SHIPPED", "only a draft or a shipment that hasn't left gets cancelled", "55000")}
  end if;
  update ${shipments} x set
    ${h("status")} = 'cancelled',
    ${h("cancelledAt")} = now(),
    ${h("updatedAt")} = now()
  where x.${h("id")} = v_ship.${h("id")}
  returning * into v_ship;
  ${ctx.record({
    type: "shipment.cancelled",
    payload: `jsonb_build_object(${base("v_ship")}, 'trackingNumber', v_ship.${h("trackingNumber")})`,
    subject: subject("v_ship"),
    tenant: `v_ship.${h("tenant")}`,
    audit: audited("v_ship", "cancelled shipment"),
  })}
  return ${shipmentJson("v_ship")};
end;
$$;
${userGrant(`${fn("cancel_shipment")}(uuid)`)}

-- A shipment's tracking timeline, oldest first.
create or replace function ${fn("list_tracking_events")}(shipment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship ${shipments}%rowtype;
begin
  select * into v_ship from ${shipments} x where x.${h("id")} = list_tracking_events.shipment_id;
  if not found or not ${allowed(`v_ship.${h("tenant")}`, read)} then
    ${fail("SHIPMENT_NOT_FOUND", "shipment not found", "P0002")}
  end if;
  return (
    select coalesce(jsonb_agg(${eventJson("t")} order by t.${e("occurredAt")}, array_position(array[${list(TRACKING_STATUSES)}]::text[], t.${e("status")})), '[]'::jsonb)
    from ${events} t
    where t.${e("shipment")} = v_ship.${h("id")}
  );
end;
$$;
${userGrant(`${fn("list_tracking_events")}(uuid)`)}
`;
}

/**
 * Moves the shipments on a merged registered subject to the record it merged
 * into.
 */
function shipmentMerges(ctx: BlockSqlContext): string {
  const subjects = registeredSubjects(ctx.subjects, ctx.naming).map(
    (subject) =>
      [
        subject.type,
        { table: `${subject.schema}.${subject.table}`, extra: {} },
      ] as const,
  );

  return subjectMergeHandler(
    ctx,
    subjects,
    moveSubjectRows(
      {
        table: ctx.table("shipments"),
        type: ctx.col("shipments", "subjectType"),
        id: ctx.col("shipments", "subjectId"),
      },
      "v_type",
    ),
  );
}

const RESERVED = ["fields", "packages", "from", "to"];

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const extras = ctx.extraColumns("shipments", RESERVED);

  return `${schemaPreamble(ctx)}
-- Shipments: packages, addresses, carrier labels and a tracking timeline
-- whose latest event sets the shipment's status.
${tables(ctx, extras)}${functions(ctx, extras)}${shipmentMerges(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const fields = extraFieldsArg(ctx.extraColumns("shipments", RESERVED));

  return [
    {
      name: "create_shipment",
      args: [
        "{id}",
        "jsonb",
        "jsonb",
        "jsonb",
        "text",
        "uuid",
        "text",
        "text",
        ...fields.contract,
      ],
      returns: "jsonb",
    },
    { name: "get_shipment", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_shipments",
      args: ["{id}", "text", "text", "text", "text", "timestamptz", "integer"],
      returns: "jsonb",
    },
    {
      name: "set_shipment_label",
      args: [
        "uuid",
        "text",
        "text",
        "text",
        "text",
        "bigint",
        "text",
        "text",
        "text",
        "text",
      ],
      returns: "jsonb",
    },
    {
      name: "record_tracking_events",
      args: ["uuid", "jsonb", "text"],
      returns: "jsonb",
    },
    {
      name: "ingest_tracking_events",
      args: ["text", "text", "jsonb"],
      returns: "jsonb",
    },
    { name: "cancel_shipment", args: ["uuid"], returns: "jsonb" },
    { name: "list_tracking_events", args: ["uuid"], returns: "jsonb" },
  ];
}

export const SHIPMENTS: BlockSqlDefinition = {
  name: "shipments",
  scopes: ["tenant"],
  title: "Shipments",
  description:
    "Shipments with packages and addresses, labels bought through a versioned carrier interface, and a tracking timeline fed by polling or verified carrier webhooks, with the shipment's status taken from its latest tracking event.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "audit", "assets"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
