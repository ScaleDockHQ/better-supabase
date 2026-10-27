import type { BookingsEvents } from "../../blocks/bookings/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";
import type { Parts } from "./bookings-public.ts";

import { sqlIdent } from "../../core/template.ts";
import { guestOr } from "../guest-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  fail,
  lockTable,
  schemaPreamble,
  serviceGrant,
  sha256Hex,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import {
  BOOKINGS_CONTRIBUTES,
  hostBusy,
  allowed,
  bookingJson as bookingJsonOf,
  calendarMirror,
  live,
  publicBooking,
  record,
  recurringOn,
  reminderMirror,
  slotsJson,
} from "./bookings-public.ts";
import {
  SERIES_TABLES,
  seriesContract,
  seriesFunctions,
  seriesTables,
} from "./bookings-series.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The queue a hold enqueues to expire itself once `hold_expires_at` passes. */
const BOOKING_EXPIRE_QUEUE = "bookings.expire-holds";

const PAYLOAD = ["organizationId", "id", "resourceId", "serviceId"] as const;

const EVENTS: BlockSqlEvents<BookingsEvents> = {
  "booking.reserved": { subject: "bookings", payload: PAYLOAD },
  "booking.confirmed": { subject: "bookings", payload: PAYLOAD },
  "booking.cancelled": { subject: "bookings", payload: PAYLOAD },
  "booking.expired": { subject: "bookings", payload: PAYLOAD },
  "booking.rescheduled": { subject: "bookings", payload: PAYLOAD },
};

const NAMES: BlockSqlNames = {
  entities: {
    booking: {
      table: "bookings",
      singular: "booking",
      primary: true,
      subject: {
        title: "customerName",
        permissions: { read: "read", write: "manage" },
      },
    },
  },
  events: EVENTS,
  hooks: [
    "before_booking_reserve",
    "after_booking_reserve",
    "after_booking_confirm",
    "after_booking_cancel",
  ],
  options: ["extraColumns", "recurring"],
  tables: {
    resources: {
      name: "booking_resources",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        kind: "kind",
        capacity: "capacity",
        tz: "tz",
        calendar: "calendar_id",
        host: "host_user_id",
        checkBusy: "check_busy",
        active: "active",
        createdAt: "created_at",
      },
      optional: ["calendar", "host", "checkBusy"],
    },
    availability: {
      name: "booking_availability",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        resource: "resource_id",
        weekday: "weekday",
        startsAt: "starts_at",
        endsAt: "ends_at",
      },
    },
    exceptions: {
      name: "booking_exceptions",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        resource: "resource_id",
        during: "during",
        available: "available",
        reason: "reason",
      },
    },
    services: {
      name: "booking_services",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        duration: "duration",
        bufferBefore: "buffer_before",
        bufferAfter: "buffer_after",
        resourceKinds: "resource_kinds",
        step: "step",
        minNotice: "min_notice",
        holdFor: "hold_for",
        reminderOffsets: "reminder_offsets",
        active: "active",
        createdAt: "created_at",
      },
      optional: ["reminderOffsets"],
    },
    bookings: {
      name: "bookings",
      app: {},
      lifecycle: { tenant: "tenant", user: "customerUser", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        resource: "resource_id",
        service: "service_id",
        seat: "seat",
        during: "during",
        blocked: "blocked",
        status: "status",
        holdExpiresAt: "hold_expires_at",
        customerName: "customer_name",
        customerEmail: "customer_email",
        customerUser: "customer_user_id",
        notes: "notes",
        accessHash: "access_hash",
        calendarEvent: "calendar_event_id",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
        cancelledAt: "cancelled_at",
        cancelReason: "cancel_reason",
        series: "series_id",
      },
      optional: ["notes", "calendarEvent", "createdBy", "series"],
      typed: ["status"],
    },
    ...SERIES_TABLES,
  },
};

function tables(p: Parts): string {
  const { ctx, r, av, x, s, b } = p;

  if (!ctx.manages) {
    return "";
  }

  return `create extension if not exists btree_gist with schema extensions;
create table if not exists ${p.resources} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("name")} text not null check (length(${r("name")}) between 1 and 120),
  ${r("kind")} text not null default 'staff',
  ${r("capacity")} integer not null default 1 check (${r("capacity")} between 1 and 1000),
  ${r("tz")} text not null default 'UTC',
  ${r("calendar")} uuid,
  ${r("host")} uuid,
  ${r("checkBusy")} boolean not null default false,
  ${r("active")} boolean not null default true,
  ${r("createdAt")} timestamptz not null default now()
);
alter table ${p.resources} add column if not exists ${r("host")} uuid;
alter table ${p.resources} add column if not exists ${r("checkBusy")} boolean not null default false;
${lockTable(p.resources, { read: true })}
create index if not exists ${sqlIdent(`${ctx.tableName("resources").name}_tenant_idx`)} on ${p.resources} (${r("tenant")});
${renderPolicy(makePolicy({ table: p.resources, name: ctx.naming.rename("booking_resources_read"), command: "select", roles: ["authenticated"], using: `${ctx.scope.check(r("tenant"), p.read)} or ${ctx.scope.check(r("tenant"), p.create)}` }), { drop: true, target: p.resources })}
create table if not exists ${p.availability} (
  ${av("id")} uuid primary key default gen_random_uuid(),
  ${av("tenant")} ${ctx.idType} not null,
  ${av("resource")} uuid not null references ${p.resources} (${r("id")}) on delete cascade,
  ${av("weekday")} smallint not null check (${av("weekday")} between 1 and 7),
  ${av("startsAt")} time not null,
  ${av("endsAt")} time not null,
  check (${av("endsAt")} > ${av("startsAt")})
);
create index if not exists ${ctx.naming.rename("booking_availability_resource_idx")} on ${p.availability} (${av("resource")}, ${av("weekday")});
${lockTable(p.availability, { read: true })}
${renderPolicy(makePolicy({ table: p.availability, name: ctx.naming.rename("booking_availability_read"), command: "select", roles: ["authenticated"], using: `${ctx.scope.check(av("tenant"), p.read)} or ${ctx.scope.check(av("tenant"), p.create)}` }), { drop: true, target: p.availability })}
create table if not exists ${p.exceptions} (
  ${x("id")} uuid primary key default gen_random_uuid(),
  ${x("tenant")} ${ctx.idType} not null,
  ${x("resource")} uuid not null references ${p.resources} (${r("id")}) on delete cascade,
  ${x("during")} tstzrange not null check (not isempty(${x("during")})),
  ${x("available")} boolean not null default false,
  ${x("reason")} text
);
create index if not exists ${ctx.naming.rename("booking_exceptions_resource_idx")} on ${p.exceptions} using gist (${x("resource")}, ${x("during")});
${lockTable(p.exceptions, { read: true })}
${renderPolicy(makePolicy({ table: p.exceptions, name: ctx.naming.rename("booking_exceptions_read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(x("tenant"), p.read) }), { drop: true, target: p.exceptions })}
create table if not exists ${p.services} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("name")} text not null check (length(${s("name")}) between 1 and 120),
  ${s("duration")} interval not null check (${s("duration")} > interval '0'),
  ${s("bufferBefore")} interval not null default interval '0' check (${s("bufferBefore")} >= interval '0'),
  ${s("bufferAfter")} interval not null default interval '0' check (${s("bufferAfter")} >= interval '0'),
  ${s("resourceKinds")} text[] not null default '{}',
  ${s("step")} interval check (${s("step")} > interval '0'),
  ${s("minNotice")} interval not null default interval '0',
  ${s("holdFor")} interval not null default interval '10 minutes' check (${s("holdFor")} > interval '0'),
  ${s("reminderOffsets")} integer[] not null default '{1440}',
  ${s("active")} boolean not null default true,
  ${s("createdAt")} timestamptz not null default now()
);
${lockTable(p.services, { read: true })}
create index if not exists ${sqlIdent(`${ctx.tableName("services").name}_tenant_idx`)} on ${p.services} (${s("tenant")});
${renderPolicy(makePolicy({ table: p.services, name: ctx.naming.rename("booking_services_read"), command: "select", roles: ["authenticated"], using: `${ctx.scope.check(s("tenant"), p.read)} or ${ctx.scope.check(s("tenant"), p.create)}` }), { drop: true, target: p.services })}
create table if not exists ${p.bookings} (
  ${b("id")} uuid primary key default gen_random_uuid(),
  ${b("tenant")} ${ctx.idType} not null,
  ${b("resource")} uuid not null references ${p.resources} (${r("id")}) on delete cascade,
  ${b("service")} uuid not null references ${p.services} (${s("id")}) on delete restrict,
  ${b("seat")} integer not null default 1 check (${b("seat")} >= 1),
  ${b("during")} tstzrange not null check (not isempty(${b("during")})),
  ${b("blocked")} tstzrange not null,
  ${b("status")} text not null default 'hold' check (${b("status")} in ('hold', 'confirmed', 'cancelled')),
  ${b("holdExpiresAt")} timestamptz,
  ${b("customerName")} text,
  ${b("customerEmail")} text,
  ${b("customerUser")} uuid,
  ${b("notes")} text,
  ${b("accessHash")} text unique,
  ${b("calendarEvent")} uuid,
  ${b("createdBy")} uuid,
  ${b("createdAt")} timestamptz not null default now(),
  ${b("updatedAt")} timestamptz not null default now(),
  ${b("cancelledAt")} timestamptz,
  ${b("cancelReason")} text,
  check (${b("blocked")} @> ${b("during")}),
  check ((${b("status")} = 'hold') = (${b("holdExpiresAt")} is not null)),
  constraint ${ctx.naming.rename("bookings_no_overlap")} exclude using gist (
    ${b("resource")} with =,
    ${b("seat")} with =,
    ${b("blocked")} with &&
  ) where (${b("status")} <> 'cancelled')
);
create index if not exists ${ctx.naming.rename("bookings_tenant_during_idx")} on ${p.bookings} using gist (${b("tenant")}, ${b("during")});
create index if not exists ${ctx.naming.rename("bookings_resource_idx")} on ${p.bookings} (${b("resource")});
create index if not exists ${ctx.naming.rename("bookings_service_idx")} on ${p.bookings} (${b("service")});
create index if not exists ${ctx.naming.rename("bookings_hold_idx")} on ${p.bookings} (${b("holdExpiresAt")}) where ${b("status")} = 'hold';${addExtraColumns(p.bookings, p.extras)}
${lockTable(p.bookings, { read: true })}
${renderPolicy(makePolicy({ table: p.bookings, name: ctx.naming.rename("bookings_read"), command: "select", roles: ["authenticated"], using: guestOr(`${ctx.scope.check(b("tenant"), p.read)} or ${b("customerUser")} = (select auth.uid())`, [ctx.scope.guest(b("tenant"), "'booking'", `${b("id")}::text`, "read")]) }), { drop: true, target: p.bookings })}
${recurringOn(ctx) ? seriesTables(p) : ""}`;
}

function setup(p: Parts): string {
  const { ctx, r, av, x, s } = p;
  const fn = (name: string) => ctx.fn(name);

  const resourceFields: readonly (readonly [string, string, string])[] = [
    ["name", r("name"), "v_item ->> 'name'"],
    ["kind", r("kind"), "v_item ->> 'kind'"],
    ["capacity", r("capacity"), "(v_item ->> 'capacity')::integer"],
    ["tz", r("tz"), "v_item ->> 'tz'"],
    ["active", r("active"), "(v_item ->> 'active')::boolean"],
    ...(ctx.has("resources", "calendar")
      ? [
          [
            "calendarId",
            r("calendar"),
            "nullif(v_item ->> 'calendarId', '')::uuid",
          ] as const,
        ]
      : []),
    ...(ctx.has("resources", "host")
      ? [
          [
            "hostUserId",
            r("host"),
            "nullif(v_item ->> 'hostUserId', '')::uuid",
          ] as const,
        ]
      : []),
    ...(ctx.has("resources", "checkBusy")
      ? [
          [
            "checkBusy",
            r("checkBusy"),
            "(v_item ->> 'checkBusy')::boolean",
          ] as const,
        ]
      : []),
  ];

  const serviceFields: readonly (readonly [string, string, string])[] = [
    ["name", s("name"), "v_item ->> 'name'"],
    ["duration", s("duration"), "(v_item ->> 'duration')::interval"],
    [
      "bufferBefore",
      s("bufferBefore"),
      "(v_item ->> 'bufferBefore')::interval",
    ],
    ["bufferAfter", s("bufferAfter"), "(v_item ->> 'bufferAfter')::interval"],
    [
      "resourceKinds",
      s("resourceKinds"),
      "array(select jsonb_array_elements_text(v_item -> 'resourceKinds'))",
    ],
    ["step", s("step"), "nullif(v_item ->> 'step', '')::interval"],
    ["minNotice", s("minNotice"), "(v_item ->> 'minNotice')::interval"],
    ["holdFor", s("holdFor"), "(v_item ->> 'holdFor')::interval"],
    ["active", s("active"), "(v_item ->> 'active')::boolean"],
    ...(ctx.has("services", "reminderOffsets")
      ? [
          [
            "reminderOffsets",
            s("reminderOffsets"),
            "array(select jsonb_array_elements_text(v_item -> 'reminderOffsets')::integer)",
          ] as const,
        ]
      : []),
  ];

  const defaultOf = (column: string): string =>
    ({
      [r("kind")]: "'staff'",
      [r("capacity")]: "1",
      [r("tz")]: "'UTC'",
      [r("active")]: "true",
      [r("checkBusy")]: "false",
      [s("bufferBefore")]: "interval '0'",
      [s("bufferAfter")]: "interval '0'",
      [s("resourceKinds")]: "'{}'::text[]",
      [s("minNotice")]: "interval '0'",
      [s("holdFor")]: "interval '10 minutes'",
      [s("active")]: "true",
      [s("reminderOffsets")]: "'{1440}'::integer[]",
    })[column] ?? "null";

  const upsert = (
    table: string,
    id: string,
    tenantCol: string,
    fields: readonly (readonly [string, string, string])[],
  ) => `if v_id is null then
    insert into ${table} (${tenantCol}, ${fields.map(([, column]) => column).join(", ")})
    values (v_tenant, ${fields.map(([key, column, value]) => `case when v_item ? '${key}' then ${value} else ${defaultOf(column)} end`).join(", ")})
    returning ${id} into v_id;
  else
    update ${table} set ${fields.map(([key, column, value]) => `${column} = case when v_item ? '${key}' then ${value} else ${column} end`).join(", ")}
    where ${id} = v_id and ${tenantCol} = v_tenant;
    if not found then
      ${fail("BOOKING_NOT_FOUND", "not found", "P0002")}
    end if;
  end if;`;

  return `
create or replace function ${fn("save_booking_resource")}(tenant ${ctx.idType}, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_resource.item, '{}'::jsonb);
  v_tenant ${ctx.idType} := save_booking_resource.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not ${allowed(p.scope, "v_tenant", p.manage)} then
    ${fail("BOOKING_FORBIDDEN", "not allowed to manage bookings")}
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_item ->> 'tz') then
    ${fail("BOOKING_TZ_INVALID", "tz must be an IANA time zone", "22023")}
  end if;
  ${upsert(p.resources, r("id"), r("tenant"), resourceFields)}
  return jsonb_build_object('id', v_id);
end;
$$;
${userGrant(`${fn("save_booking_resource")}(${ctx.idType}, jsonb)`)}

-- Replaces a resource's weekly hours with source.hours: { weekday (1 is
-- Monday), start, end } in the resource's time zone.
create or replace function ${fn("set_booking_availability")}(resource uuid, source jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_count integer;
begin
  select ${r("tenant")} into v_tenant from ${p.resources} where ${r("id")} = set_booking_availability.resource;
  if not found then
    ${fail("BOOKING_RESOURCE_NOT_FOUND", "resource not found", "P0002")}
  end if;
  if not ${allowed(p.scope, "v_tenant", p.manage)} then
    ${fail("BOOKING_FORBIDDEN", "not allowed to manage bookings")}
  end if;
  delete from ${p.availability} where ${av("resource")} = set_booking_availability.resource;
  insert into ${p.availability} (${av("tenant")}, ${av("resource")}, ${av("weekday")}, ${av("startsAt")}, ${av("endsAt")})
  select v_tenant, set_booking_availability.resource, (h ->> 'weekday')::smallint, (h ->> 'start')::time, (h ->> 'end')::time
  from jsonb_array_elements(coalesce(set_booking_availability.source -> 'hours', '[]'::jsonb)) h;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${userGrant(`${fn("set_booking_availability")}(uuid, jsonb)`)}

-- Closes a resource for a range (a holiday, a meeting), or opens it outside
-- its weekly hours with available = true.
create or replace function ${fn("add_booking_exception")}(resource uuid, starts_at timestamptz, ends_at timestamptz, available boolean, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_id uuid;
begin
  select ${r("tenant")} into v_tenant from ${p.resources} where ${r("id")} = add_booking_exception.resource;
  if not found then
    ${fail("BOOKING_RESOURCE_NOT_FOUND", "resource not found", "P0002")}
  end if;
  if not ${allowed(p.scope, "v_tenant", p.manage)} then
    ${fail("BOOKING_FORBIDDEN", "not allowed to manage bookings")}
  end if;
  if add_booking_exception.ends_at is null or add_booking_exception.starts_at is null or add_booking_exception.ends_at <= add_booking_exception.starts_at then
    ${fail("BOOKING_RANGE_INVALID", "an exception needs a start before its end", "22023")}
  end if;
  insert into ${p.exceptions} (${x("tenant")}, ${x("resource")}, ${x("during")}, ${x("available")}, ${x("reason")})
  values (v_tenant, add_booking_exception.resource, tstzrange(add_booking_exception.starts_at, add_booking_exception.ends_at), coalesce(add_booking_exception.available, false), add_booking_exception.reason)
  returning ${x("id")} into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
${userGrant(`${fn("add_booking_exception")}(uuid, timestamptz, timestamptz, boolean, text)`)}

create or replace function ${fn("delete_booking_exception")}(exception_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
begin
  select ${x("tenant")} into v_tenant from ${p.exceptions} where ${x("id")} = delete_booking_exception.exception_id;
  if not found then
    return false;
  end if;
  if not ${allowed(p.scope, "v_tenant", p.manage)} then
    ${fail("BOOKING_FORBIDDEN", "not allowed to manage bookings")}
  end if;
  delete from ${p.exceptions} where ${x("id")} = delete_booking_exception.exception_id;
  return true;
end;
$$;
${userGrant(`${fn("delete_booking_exception")}(uuid)`)}

create or replace function ${fn("save_booking_service")}(tenant ${ctx.idType}, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_service.item, '{}'::jsonb);
  v_tenant ${ctx.idType} := save_booking_service.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not ${allowed(p.scope, "v_tenant", p.manage)} then
    ${fail("BOOKING_FORBIDDEN", "not allowed to manage bookings")}
  end if;
  ${upsert(p.services, s("id"), s("tenant"), serviceFields)}
  return jsonb_build_object('id', v_id);
end;
$$;
${userGrant(`${fn("save_booking_service")}(${ctx.idType}, jsonb)`)}
`;
}

function slots(p: Parts): string {
  const { ctx, r, av, x, s, b } = p;
  const fn = (name: string) => ctx.fn(name);

  return `
-- The open slots of a service in [range_start, range_end): for each resource
-- of the service's kinds, its weekly hours in its own time zone, plus the
-- exceptions that open it, minus the ones that close it. Slots start at the
-- opening time and every step (default the duration) after it, and a slot is
-- open while a seat's bookings, buffers included, leave room for it. A
-- resource with a host and check_busy also needs the host free in the
-- calendar (events, out of office, focus time, leave) over the slot and its
-- buffers. local_start is the start in tz (default the resource's zone).
create or replace function ${fn("booking_slots")}(service uuid, range_start timestamptz, range_end timestamptz, tz text, only_resource uuid)
returns table (resource_id uuid, starts_at timestamptz, ends_at timestamptz, local_start timestamp, seats integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_service record;
  v_resource record;
  v_open tstzmultirange;
  v_window tstzrange;
  v_floor timestamptz;
  v_step interval;
  v_at timestamptz;
  v_block tstzrange;
  v_free integer;
  v_busy tstzmultirange := '{}'::tstzmultirange;
begin
  select sv.${s("tenant")} as tenant, sv.${s("duration")} as duration, sv.${s("bufferBefore")} as before, sv.${s("bufferAfter")} as after,
      sv.${s("resourceKinds")} as kinds, sv.${s("step")} as step, sv.${s("minNotice")} as notice
    into v_service
    from ${p.services} sv where sv.${s("id")} = booking_slots.service and sv.${s("active")};
  if not found or booking_slots.range_end is null or booking_slots.range_start is null then
    return;
  end if;
  v_step := coalesce(v_service.step, v_service.duration);
  v_floor := greatest(booking_slots.range_start, now() + v_service.notice);
  for v_resource in
    select rs.${r("id")} as id, rs.${r("tz")} as tz, rs.${r("capacity")} as capacity${hostBusy(p) ? `, case when rs.${r("checkBusy")} then rs.${r("host")} end as host` : ""}
    from ${p.resources} rs
    where rs.${r("tenant")} = v_service.tenant and rs.${r("active")}
      and (cardinality(v_service.kinds) = 0 or rs.${r("kind")} = any (v_service.kinds))
      and (booking_slots.only_resource is null or rs.${r("id")} = booking_slots.only_resource)
    order by rs.${r("name")}, rs.${r("id")}
  loop
    select coalesce(range_agg(tstzrange((d.day + a.${av("startsAt")}) at time zone v_resource.tz, (d.day + a.${av("endsAt")}) at time zone v_resource.tz)), '{}'::tstzmultirange)
      into v_open
      from (
        select g::date as day
        from generate_series((v_floor at time zone v_resource.tz)::date - 1, (booking_slots.range_end at time zone v_resource.tz)::date, interval '1 day') g
      ) d
      join ${p.availability} a on a.${av("resource")} = v_resource.id and a.${av("weekday")} = extract(isodow from d.day)::integer;
    v_open := v_open + coalesce((select range_agg(e.${x("during")}) from ${p.exceptions} e where e.${x("resource")} = v_resource.id and e.${x("available")}), '{}'::tstzmultirange);
    v_open := v_open - coalesce((select range_agg(e.${x("during")}) from ${p.exceptions} e where e.${x("resource")} = v_resource.id and not e.${x("available")}), '{}'::tstzmultirange);${hostBusy(p) ? `\n    ${hostBusy(p)}` : ""}
    for v_window in select w from unnest(v_open) w loop
      v_at := lower(v_window);
      if v_at < v_floor then
        v_at := v_at + ceil(extract(epoch from (v_floor - v_at)) / extract(epoch from v_step)) * v_step;
      end if;
      while v_at + v_service.duration <= upper(v_window) and v_at + v_service.duration <= booking_slots.range_end loop
        v_block := tstzrange(v_at - v_service.before, v_at + v_service.duration + v_service.after);
        select count(*)::integer into v_free
        from generate_series(1, v_resource.capacity) seat
        where not exists (
          select 1 from ${p.bookings} bk
          where bk.${b("resource")} = v_resource.id and bk.${b("seat")} = seat.seat
            and ${live(p, "bk")} and bk.${b("blocked")} && v_block
        );
        if v_free > 0 and not (v_busy && v_block) then
          resource_id := v_resource.id;
          starts_at := v_at;
          ends_at := v_at + v_service.duration;
          local_start := v_at at time zone coalesce(booking_slots.tz, v_resource.tz);
          seats := v_free;
          return next;
        end if;
        v_at := v_at + v_step;
      end loop;
    end loop;
  end loop;
end;
$$;
${serviceGrant(`${fn("booking_slots")}(uuid, timestamptz, timestamptz, text, uuid)`)}

create or replace function ${fn("available_slots")}(service uuid, range_start timestamptz, range_end timestamptz, tz text default null, resource uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
begin
  select ${s("tenant")} into v_tenant from ${p.services} where ${s("id")} = available_slots.service;
  if not found then
    ${fail("BOOKING_SERVICE_NOT_FOUND", "service not found", "P0002")}
  end if;
  if not (${allowed(p.scope, "v_tenant", p.read)} or ${allowed(p.scope, "v_tenant", p.create)}) then
    ${fail("BOOKING_FORBIDDEN", "not allowed to read bookings")}
  end if;
  if available_slots.tz is not null and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = available_slots.tz) then
    ${fail("BOOKING_TZ_INVALID", "tz must be an IANA time zone", "22023")}
  end if;
  if available_slots.range_end - available_slots.range_start > interval '62 days' then
    ${fail("BOOKING_RANGE_INVALID", "ask for at most 62 days of slots", "22023")}
  end if;
  return ${slotsJson(fn("booking_slots"), "available_slots.service", "available_slots.range_start", "available_slots.range_end", "available_slots.tz", "available_slots.resource")};
end;
$$;
${userGrant(`${fn("available_slots")}(uuid, timestamptz, timestamptz, text, uuid)`)}
`;
}

function lifecycle(p: Parts): string {
  const { ctx, r, s, b } = p;
  const fn = (name: string) => ctx.fn(name);
  const jobs = ctx.installed("queue") ? ctx.of("queue") : undefined;

  const expireJob =
    jobs === undefined
      ? ""
      : `if v_status = 'hold' then
    perform ${jobs.fn("enqueue_job")}(queue => '${BOOKING_EXPIRE_QUEUE}', payload => jsonb_build_object('bookingId', v_id), delay => ceil(extract(epoch from (v_expires - now())))::integer + 1, dedupe_key => 'bookings:expire:' || v_id::text, dedupe_running => false);
  end if;`;

  const bookingJson = (alias: string): string => bookingJsonOf(p, alias);

  const declareMirror = `v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;`;

  return `
-- Cancels holds whose time is up: all of them, or those of one resource that
-- overlap a range. Records booking.expired for each.
create or replace function ${fn("expire_booking_holds_in")}(resource uuid, during tstzrange)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking ${p.bookings}%rowtype;
  v_count integer := 0;
begin
  for v_booking in
    update ${p.bookings} bk set ${b("status")} = 'cancelled', ${b("holdExpiresAt")} = null, ${b("cancelledAt")} = now(), ${b("cancelReason")} = 'expired', ${b("updatedAt")} = now()
    where bk.${b("status")} = 'hold' and bk.${b("holdExpiresAt")} <= now()
      and (expire_booking_holds_in.resource is null or bk.${b("resource")} = expire_booking_holds_in.resource)
      and (expire_booking_holds_in.during is null or bk.${b("blocked")} && expire_booking_holds_in.during)
    returning bk.*
  loop
    v_count := v_count + 1;
    ${record(p, "booking.expired", `v_booking.${b("id")}`, `v_booking.${b("tenant")}`)}
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("expire_booking_holds_in")}(uuid, tstzrange)`)}

create or replace function ${fn("expire_booking_holds")}()
returns integer
language sql
security definer
set search_path = ''
as $$
  select ${fn("expire_booking_holds_in")}(null, null)
$$;
${serviceGrant(`${fn("expire_booking_holds")}()`)}

-- Places a booking on a free seat. The slot must be one booking_slots
-- returns; the exclusion constraint settles a race between two callers.
create or replace function ${fn("place_booking")}(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean, customer_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(place_booking.customer, '{}'::jsonb);
  v_service ${p.services}%rowtype;
  v_capacity integer;
  v_during tstzrange;
  v_blocked tstzrange;
  v_status text := case when coalesce(place_booking.confirm, false) then 'confirmed' else 'hold' end;
  v_expires timestamptz;
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_id uuid;
  v_seat integer;
  v_booking ${p.bookings}%rowtype;
  ${declareMirror}
begin
  select * into v_service from ${p.services} sv where sv.${s("id")} = place_booking.service and sv.${s("active")};
  if not found then
    ${fail("BOOKING_SERVICE_NOT_FOUND", "service not found", "P0002")}
  end if;
  select rs.${r("capacity")} into v_capacity from ${p.resources} rs
    where rs.${r("id")} = place_booking.resource and rs.${r("tenant")} = v_service.${s("tenant")} and rs.${r("active")};
  if not found then
    ${fail("BOOKING_RESOURCE_NOT_FOUND", "resource not found", "P0002")}
  end if;
  v_during := tstzrange(place_booking.starts_at, place_booking.starts_at + v_service.${s("duration")});
  v_blocked := tstzrange(place_booking.starts_at - v_service.${s("bufferBefore")}, upper(v_during) + v_service.${s("bufferAfter")});
  ${p.ctx.hook("before_booking_reserve", [
    [ctx.idType, `v_service.${s("tenant")}`],
    ["uuid", "place_booking.service"],
    ["uuid", "place_booking.resource"],
    ["tstzrange", "v_during"],
    ["jsonb", "v_customer"],
  ])}
  perform ${fn("expire_booking_holds_in")}(place_booking.resource, v_blocked);
  if not exists (
    select 1 from ${fn("booking_slots")}(place_booking.service, place_booking.starts_at, upper(v_during), null, place_booking.resource) t
    where t.starts_at = place_booking.starts_at
  ) then
    ${fail("BOOKING_SLOT_UNAVAILABLE", "that time is not an open slot", "23P01")}
  end if;
  if v_status = 'hold' then
    v_expires := now() + v_service.${s("holdFor")};
  end if;
  for v_seat in 1..v_capacity loop
    begin
      insert into ${p.bookings} (${b("tenant")}, ${b("resource")}, ${b("service")}, ${b("seat")}, ${b("during")}, ${b("blocked")}, ${b("status")}, ${b("holdExpiresAt")}, ${b("customerName")}, ${b("customerEmail")}, ${b("customerUser")}${ctx.has("bookings", "notes") ? `, ${b("notes")}` : ""}, ${b("accessHash")}${ctx.has("bookings", "createdBy") ? `, ${b("createdBy")}` : ""})
      values (v_service.${s("tenant")}, place_booking.resource, place_booking.service, v_seat, v_during, v_blocked, ${ctx.cast("bookings", "status", "v_status")}, v_expires, v_customer ->> 'name', lower(v_customer ->> 'email'), place_booking.customer_user${ctx.has("bookings", "notes") ? ", v_customer ->> 'notes'" : ""}, ${sha256Hex("convert_to(v_token, 'utf8')")}${ctx.has("bookings", "createdBy") ? ", auth.uid()" : ""})
      returning * into v_booking;
      v_id := v_booking.${b("id")};
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if v_id is null then
    ${fail("BOOKING_SLOT_UNAVAILABLE", "that time was just taken", "23P01")}
  end if;${writeExtraColumns(p.bookings, p.extras, "v_customer", `x.${b("id")} = v_id`, "v_booking")}
  ${record(p, "booking.reserved", "v_id", `v_booking.${b("tenant")}`)}
  if v_status = 'confirmed' then
    ${calendarMirror(p, "confirm")}
    ${reminderMirror(p, "confirm")}
    ${record(p, "booking.confirmed", "v_id", `v_booking.${b("tenant")}`)}
    ${p.ctx.hook("after_booking_confirm", [["uuid", "v_id"]])}
  end if;
  ${expireJob}
  ${p.ctx.hook("after_booking_reserve", [["uuid", "v_id"]])}
  return ${bookingJson("v_booking")} || jsonb_build_object('accessToken', v_token);
end;
$$;
${serviceGrant(`${fn("place_booking")}(uuid, uuid, timestamptz, jsonb, boolean, uuid)`)}

-- A member books for themself (customer.userId is ignored), or a manager
-- books for anyone. confirm skips the hold.
create or replace function ${fn("hold_booking")}(service uuid, resource uuid, starts_at timestamptz, customer jsonb, confirm boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_customer jsonb := coalesce(hold_booking.customer, '{}'::jsonb);
  v_user uuid := auth.uid();
begin
  select ${s("tenant")} into v_tenant from ${p.services} where ${s("id")} = hold_booking.service;
  if not found then
    ${fail("BOOKING_SERVICE_NOT_FOUND", "service not found", "P0002")}
  end if;
  if ${allowed(p.scope, "v_tenant", p.manage)} then
    v_user := coalesce(nullif(v_customer ->> 'userId', '')::uuid, v_user);
  elsif not ${allowed(p.scope, "v_tenant", p.create)} then
    ${fail("BOOKING_FORBIDDEN", "not allowed to book")}
  else
    v_customer := v_customer || jsonb_build_object('email', coalesce(v_customer ->> 'email', auth.email()));
  end if;
  return ${fn("place_booking")}(hold_booking.service, hold_booking.resource, hold_booking.starts_at, v_customer, hold_booking.confirm, v_user);
end;
$$;
${userGrant(`${fn("hold_booking")}(uuid, uuid, timestamptz, jsonb, boolean)`)}

-- Confirms or cancels a booking: a manager, the customer, or the holder of
-- its access token (public functions pass it).
create or replace function ${fn("change_booking")}(booking uuid, to_status text, reason text, access_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking ${p.bookings}%rowtype;
  v_id uuid := change_booking.booking;
  ${declareMirror}
begin
  select * into v_booking from ${p.bookings} bk where bk.${b("id")} = v_id for update;
  if not found then
    ${fail("BOOKING_NOT_FOUND", "booking not found", "P0002")}
  end if;
  if not (
    ${allowed(p.scope, `v_booking.${b("tenant")}`, p.manage)}
    or (change_booking.access_token is not null and v_booking.${b("accessHash")} = ${sha256Hex("convert_to(change_booking.access_token, 'utf8')")})
    or (change_booking.access_token is null and coalesce(v_booking.${b("customerUser")} = auth.uid(), false) and ${allowed(p.scope, `v_booking.${b("tenant")}`, p.create)})
  ) then
    ${fail("BOOKING_FORBIDDEN", "not allowed to change this booking")}
  end if;
  if change_booking.to_status = 'confirmed' then
    if v_booking.${b("status")} = 'confirmed' then
      return ${bookingJson("v_booking")};
    end if;
    if v_booking.${b("status")} <> 'hold' or v_booking.${b("holdExpiresAt")} <= now() then
      ${fail("BOOKING_HOLD_EXPIRED", "the hold has expired or was cancelled", "22023")}
    end if;
    update ${p.bookings} bk set ${b("status")} = 'confirmed', ${b("holdExpiresAt")} = null, ${b("updatedAt")} = now()
    where bk.${b("id")} = v_id returning * into v_booking;
    ${calendarMirror(p, "confirm")}
    ${reminderMirror(p, "confirm")}
    ${record(p, "booking.confirmed", "v_id", `v_booking.${b("tenant")}`)}
    ${p.ctx.hook("after_booking_confirm", [["uuid", "v_id"]])}
  elsif change_booking.to_status = 'cancelled' then
    if v_booking.${b("status")} = 'cancelled' then
      return ${bookingJson("v_booking")};
    end if;
    update ${p.bookings} bk set ${b("status")} = 'cancelled', ${b("holdExpiresAt")} = null, ${b("cancelledAt")} = now(), ${b("cancelReason")} = change_booking.reason, ${b("updatedAt")} = now()
    where bk.${b("id")} = v_id returning * into v_booking;
    ${calendarMirror(p, "cancel")}
    ${reminderMirror(p, "cancel")}
    ${record(p, "booking.cancelled", "v_id", `v_booking.${b("tenant")}`)}
    ${p.ctx.hook("after_booking_cancel", [["uuid", "v_id"]])}
  else
    ${fail("BOOKING_STATUS_INVALID", "change a booking to confirmed or cancelled", "22023")}
  end if;
  return ${bookingJson("v_booking")};
end;
$$;
${serviceGrant(`${fn("change_booking")}(uuid, text, text, text)`)}

create or replace function ${fn("confirm_booking")}(booking uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select ${fn("change_booking")}(confirm_booking.booking, 'confirmed', null, null)
$$;
${userGrant(`${fn("confirm_booking")}(uuid)`)}

create or replace function ${fn("cancel_booking")}(booking uuid, reason text default null)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select ${fn("change_booking")}(cancel_booking.booking, 'cancelled', cancel_booking.reason, null)
$$;
${userGrant(`${fn("cancel_booking")}(uuid, text)`)}

-- The bookings that overlap [range_start, range_end), as the caller: the
-- table's policy shows a tenant's bookings to readers and a customer their own.
create or replace function ${fn("list_bookings")}(tenant ${ctx.idType}, range_start timestamptz, range_end timestamptz, resource uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${bookingJson("bk")} order by lower(bk.${b("during")}), bk.${b("id")}), '[]'::jsonb)
  from ${p.bookings} bk
  where bk.${b("tenant")} = list_bookings.tenant
    and bk.${b("during")} && tstzrange(list_bookings.range_start, list_bookings.range_end)
    and (list_bookings.resource is null or bk.${b("resource")} = list_bookings.resource)
$$;
${userGrant(`${fn("list_bookings")}(${ctx.idType}, timestamptz, timestamptz, uuid)`)}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const perms = moduleOperations("bookings");

  const p: Parts = {
    scope: ctx.scope,
    ctx,
    r: (column) => ctx.col("resources", column),
    av: (column) => ctx.col("availability", column),
    x: (column) => ctx.col("exceptions", column),
    s: (column) => ctx.col("services", column),
    b: (column) => ctx.col("bookings", column),
    resources: ctx.table("resources"),
    availability: ctx.table("availability"),
    exceptions: ctx.table("exceptions"),
    services: ctx.table("services"),
    bookings: ctx.table("bookings"),
    manage: ctx.permission("manage", perms.manage),
    create: ctx.permission("create", perms.create),
    read: ctx.permission("read", perms.read),
    extras: ctx.extraColumns("bookings", [
      "id",
      "seat",
      "status",
      "notes",
      "name",
      "email",
      "fields",
    ]),
  };

  return `${schemaPreamble(ctx)}
${tables(p)}${setup(p)}${slots(p)}${lifecycle(p)}${publicBooking(p)}${recurringOn(ctx) ? seriesFunctions(p) : ""}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_booking_resource",
      args: ["{id}", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "set_booking_availability",
      args: ["uuid", "jsonb"],
      returns: "integer",
    },
    {
      name: "add_booking_exception",
      args: ["uuid", "timestamptz", "timestamptz", "boolean", "text"],
      returns: "jsonb",
    },
    { name: "delete_booking_exception", args: ["uuid"], returns: "boolean" },
    { name: "save_booking_service", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "available_slots",
      args: ["uuid", "timestamptz", "timestamptz", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "hold_booking",
      args: ["uuid", "uuid", "timestamptz", "jsonb", "boolean"],
      returns: "jsonb",
    },
    { name: "confirm_booking", args: ["uuid"], returns: "jsonb" },
    { name: "cancel_booking", args: ["uuid", "text"], returns: "jsonb" },
    { name: "expire_booking_holds", args: [], returns: "integer" },
    {
      name: "list_bookings",
      args: ["{id}", "timestamptz", "timestamptz", "uuid"],
      returns: "jsonb",
    },
    ...(ctx.installed("share-links")
      ? [
          { name: "public_booking_service", args: ["text"], returns: "jsonb" },
          {
            name: "public_available_slots",
            args: ["text", "timestamptz", "timestamptz", "text"],
            returns: "jsonb",
          },
          {
            name: "public_hold_booking",
            args: ["text", "uuid", "timestamptz", "jsonb"],
            returns: "jsonb",
          },
          {
            name: "public_change_booking",
            args: ["uuid", "text", "text"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(recurringOn(ctx) ? seriesContract() : []),
  ];
}

export const BOOKINGS: BlockSqlDefinition = {
  contributes: BOOKINGS_CONTRIBUTES,
  name: "bookings",
  scopes: ["tenant"],
  title: "Bookings",
  description:
    "Bookable resources with weekly hours and exceptions, services with durations and buffers, and bookings that a gist exclusion constraint (btree_gist) keeps from overlapping per seat. Holds expire; recurring series book every occurrence; a share link opens public booking; confirmed bookings mirror into the calendar and reminders.",
  requires: ["memberships", "permissions"],
  integrates: [
    "queue",
    "share-links",
    "rate-limit",
    "calendar",
    "reminders",
    "outbox",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
