import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addCheck,
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  insertExtraColumns,
  lockTable,
  schemaPreamble,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { attendeesSql } from "./calendar-attendees.ts";
import {
  availabilityContract,
  availabilitySql,
  EVENT_KINDS,
  TRANSPARENCIES,
  workingHoursTable,
} from "./calendar-availability.ts";
import {
  accessCall,
  accessFunctions,
  calendarFeatures,
  eventAccessCall,
  grantFunctions,
  grantsTable,
  insertRule,
  privateCalendar,
  recurrenceSql,
  recurrenceTables,
  replaceDates,
  addDate,
} from "./calendar-features.ts";
import { feed } from "./calendar-feed.ts";
import { CALENDAR_NAMES } from "./calendar-names.ts";
import {
  eventExtras,
  eventFields,
  eventJson,
  RESPONSES,
  ROLES,
  STATUSES,
  updateSet,
} from "./calendar-rows.ts";
import { moduleOperations } from "./permissions-model.ts";
import { shareLinkRow } from "./share-links.ts";

/** The reminders rule that mirrors an event, so reminders can attach to it. */
function reminderRule(ctx: BlockSqlContext, op: "save" | "delete"): string {
  if (!ctx.installed("reminders")) {
    return "";
  }

  const r = ctx.of("reminders");

  if (!r.has("rules", "rrule")) {
    return "";
  }

  const rules = r.table("rules");
  const col = (column: string) => r.col("rules", column);

  if (op === "delete") {
    return `delete from ${rules} where ${col("subjectType")} = 'calendar_event' and ${col("subjectId")} = v_id::text;`;
  }

  return `insert into ${rules} (${col("tenant")}, ${col("subjectType")}, ${col("subjectId")}, ${col("dtstart")}, ${col("tzid")}, ${col("rrule")})
  select e.${ctx.col("events", "tenant")}, 'calendar_event', e.${ctx.col("events", "id")}::text, e.${ctx.col("events", "startsAt")}, e.${ctx.col("events", "tz")}, coalesce(${recurrenceSql(ctx).rule("e.")}, 'FREQ=DAILY;COUNT=1')
  from ${ctx.table("events")} e where e.${ctx.col("events", "id")} = v_id
  on conflict (${col("tenant")}, ${col("subjectType")}, ${col("subjectId")})
  do update set ${col("dtstart")} = excluded.${col("dtstart")}, ${col("tzid")} = excluded.${col("tzid")}, ${col("rrule")} = excluded.${col("rrule")};`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const calendars = ctx.table("calendars");
  const events = ctx.table("events");
  const attendees = ctx.hasTable("attendees") ? ctx.table("attendees") : "";
  const k = (column: string) => ctx.col("calendars", column);
  const e = (column: string) => ctx.col("events", column);
  const a = (column: string) => ctx.col("attendees", column);
  const perms = moduleOperations("calendar");
  const manage = ctx.permission("manage", perms.manage);
  const write = ctx.permission("write", perms.write);
  const read = ctx.permission("read", perms.read);
  const fn = (name: string): string => ctx.fn(name);

  const allowed = (tenant: string, key: string) =>
    `(auth.role() = 'service_role' or ${ctx.scope.can(tenant, key)})`;

  const fields = eventFields(ctx);
  const features = calendarFeatures(ctx);

  const writesCalendar = (calendar: string, tenant: string) =>
    features.access
      ? accessCall(ctx, calendar, "write")
      : allowed(tenant, write);

  const writesEvent = (event: string, tenant: string) =>
    features.access
      ? eventAccessCall(ctx, event, "write")
      : allowed(tenant, write);

  const recurrence = recurrenceSql(ctx);
  const me = "(select auth.uid())";

  const calendarColumns = `${
    features.access && ctx.has("calendars", "visibility")
      ? `
alter table ${calendars} add column if not exists ${k("visibility")} text not null default 'shared';
${addCheck({
  table: calendars,
  name: `${ctx.tableName("calendars").name}_visibility_check`,
  expression: `${k("visibility")} in ('shared', 'private')`,
})}`
      : ""
  }${
    features.details
      ? [
          ["description", "text"],
          ["rank", "text"],
          ["isDefault", "boolean not null default false"],
        ]
          .filter(([column]) => ctx.has("calendars", column!))
          .map(
            ([column, type]) =>
              `\nalter table ${calendars} add column if not exists ${k(column!)} ${type};`,
          )
          .join("")
      : ""
  }`;

  const eventColumns = `${
    features.access && ctx.has("events", "visibility")
      ? `
alter table ${events} add column if not exists ${e("visibility")} text not null default 'public';
${addCheck({
  table: events,
  name: `${ctx.tableName("events").name}_visibility_check`,
  expression: `${e("visibility")} in ('public', 'private')`,
})}`
      : ""
  }${features.access && ctx.has("events", "owner") ? `\nalter table ${events} add column if not exists ${e("owner")} uuid;` : ""}${
    features.rdates && !features.table
      ? `\nalter table ${events} add column if not exists ${e("rdates")} timestamptz[] not null default '{}';`
      : ""
  }`;

  const attendeeColumns = features.anyAttendee
    ? `${ctx.has("attendees", "email") ? `\nalter table ${attendees} alter column ${a("email")} drop not null;` : ""}${[
        ["subjectType", "text"],
        ["subjectId", "text"],
        ["organizer", "boolean not null default false"],
        ["optional", "boolean not null default false"],
      ]
        .filter(([column]) => ctx.has("attendees", column!))
        .map(
          ([column, type]) =>
            `\nalter table ${attendees} add column if not exists ${a(column!)} ${type};`,
        )
        .join("")}`
    : "";

  const calendarExtras = ctx.extraColumns(
    "calendars",
    ["fields"],
    "calendarExtraColumns",
  );

  const calendarExtra = extraFieldsArg(calendarExtras);

  const calendarRequired = insertExtraColumns(
    calendars,
    calendarExtras,
    "create_calendar.fields",
  );

  const record = (type: string, id: string, calendar: string, tenant: string) =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${tenant}, 'id', ${id}, 'calendarId', ${calendar})`,
      subject: `'calendar-events/' || ${id}::text`,
      tenant,
      audit: false,
    });

  const attendeesTable = (): string =>
    ctx.hasTable("attendees")
      ? `create table if not exists ${attendees} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("event")} uuid not null references ${events} (${e("id")}) on delete cascade,
  ${a("email")} text${features.anyAttendee ? "" : " not null"},
  ${a("name")} text,
  ${a("user")} uuid,
  ${a("role")} text not null default 'required',
  ${a("response")} text not null default 'needs-action' check (${a("response")} in ${RESPONSES}),
  unique (${a("event")}, ${a("email")})
);${attendeeColumns}
${lockTable(attendees, { read: true })}
${
  ctx.has("attendees", "role")
    ? addCheck({
        table: attendees,
        name: `${ctx.tableName("attendees").name}_role_check`,
        expression: `${a("role")} in ${ROLES}`,
      })
    : ""
}
${renderPolicy(makePolicy({ table: attendees, name: `${ctx.tableName("attendees").name}_read`, command: "select", roles: ["authenticated"], using: `${features.access ? eventAccessCall(ctx, a("event"), "read", me) : ctx.scope.check(a("tenant"), read)} or ${a("user")} = (select auth.uid())` }), { drop: true, target: attendees })}
`
      : "";

  const tables = ctx.manages
    ? `create table if not exists ${calendars} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("name")} text not null check (length(${k("name")}) between 1 and 120),
  ${k("tz")} text not null default 'UTC',
  ${k("color")} text,
  ${k("ownerType")} text,
  ${k("ownerId")} text,
  ${k("createdAt")} timestamptz not null default now()
);${addExtraColumns(calendars, calendarExtras)}${calendarColumns}
${lockTable(calendars, { read: true })}
create index if not exists ${sqlIdent(`${ctx.tableName("calendars").name}_tenant_idx`)} on ${calendars} (${k("tenant")});
${renderPolicy(makePolicy({ table: calendars, name: `${ctx.tableName("calendars").name}_read`, command: "select", roles: ["authenticated"], using: features.access ? accessCall(ctx, k("id"), "read", me) : ctx.scope.check(k("tenant"), read) }), { drop: true, target: calendars })}
create table if not exists ${events} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("calendar")} uuid not null references ${calendars} (${k("id")}) on delete cascade,
  ${e("uid")} text not null,
  ${e("title")} text not null default '',
  ${e("description")} text,
  ${e("location")} text,
  ${e("startsAt")} timestamptz not null,
  ${e("endsAt")} timestamptz not null,
  ${e("allDay")} boolean not null default false,
  ${e("tz")} text not null default 'UTC',
  ${e("status")} text not null default 'confirmed' check (${e("status")} in ${STATUSES}),
  ${e("rrule")} text,
  ${e("exdates")} timestamptz[] not null default '{}',
  ${e("recurrence")} uuid references ${events} (${e("id")}) on delete cascade,
  ${e("originalStart")} timestamptz,
  ${e("subjectType")} text,
  ${e("subjectId")} text,
  ${e("color")} text,
  ${e("kind")} text not null default 'event',
  ${e("transparency")} text not null default 'opaque',
  ${e("autoDecline")} boolean not null default false,
  ${e("createdBy")} uuid,
  ${e("createdAt")} timestamptz not null default now(),
  ${e("updatedAt")} timestamptz not null default now(),
  check (${e("endsAt")} >= ${e("startsAt")}),
  check ((${e("recurrence")} is null) = (${e("originalStart")} is null)),
  unique nulls not distinct (${e("calendar")}, ${e("uid")}, ${e("originalStart")})
);
create index if not exists ${ctx.naming.rename("calendar_events_recurrence_idx")} on ${events} (${e("recurrence")}) where ${e("recurrence")} is not null;
create index if not exists ${ctx.naming.rename("calendar_events_range_idx")} on ${events} (${e("calendar")}, ${e("startsAt")});
alter table ${events} add column if not exists ${e("kind")} text not null default 'event';
alter table ${events} add column if not exists ${e("transparency")} text not null default 'opaque';
alter table ${events} add column if not exists ${e("autoDecline")} boolean not null default false;
${addCheck({
  table: events,
  name: `${ctx.tableName("events").name}_kind_check`,
  expression: `${e("kind")} in ${EVENT_KINDS}`,
})}
${addCheck({
  table: events,
  name: `${ctx.tableName("events").name}_transparency_check`,
  expression: `${e("transparency")} in ${TRANSPARENCIES}`,
})}${eventColumns}${addExtraColumns(events, eventExtras(ctx))}
${lockTable(events, { read: true })}
${renderPolicy(makePolicy({ table: events, name: `${ctx.tableName("events").name}_read`, command: "select", roles: ["authenticated"], using: features.access ? eventAccessCall(ctx, e("id"), "read", me) : ctx.scope.check(e("tenant"), read) }), { drop: true, target: events })}
${attendeesTable()}${workingHoursTable(ctx)}${grantsTable(ctx)}${recurrenceTables(ctx)}`
    : "";

  const attendeeFunctions = attendeesSql(ctx, writesEvent);

  const attrs = features.access || features.details;

  const attrColumns: (readonly [string, string, string])[] = attrs
    ? [
        ...(features.access && ctx.has("calendars", "visibility")
          ? [
              [
                "visibility",
                k("visibility"),
                ctx.cast(
                  "calendars",
                  "visibility",
                  "coalesce(v_item ->> 'visibility', 'shared')",
                ),
              ] as const,
            ]
          : []),
        ...(ctx.has("calendars", "color")
          ? [["color", k("color"), "v_item ->> 'color'"] as const]
          : []),
        ...(features.details && ctx.has("calendars", "description")
          ? [
              [
                "description",
                k("description"),
                "v_item ->> 'description'",
              ] as const,
            ]
          : []),
        ...(features.details && ctx.has("calendars", "rank")
          ? [
              [
                "rank",
                k("rank"),
                ctx.cast("calendars", "rank", "v_item ->> 'rank'"),
              ] as const,
            ]
          : []),
        ...(features.details && ctx.has("calendars", "isDefault")
          ? [
              [
                "isDefault",
                k("isDefault"),
                "coalesce((v_item ->> 'isDefault')::boolean, false)",
              ] as const,
            ]
          : []),
      ]
    : [];

  const defaults = features.details && ctx.has("calendars", "isDefault");

  const clearDefault = (id: string, tenant: string) =>
    defaults
      ? `
  if coalesce((v_item ->> 'isDefault')::boolean, false) then
    update ${calendars} set ${k("isDefault")} = false
    where ${k("tenant")} = ${tenant} and ${k("id")} <> ${id} and ${k("isDefault")}${
      ctx.has("calendars", "ownerId")
        ? `
      and ${k("ownerId")}::text is not distinct from (select x.${k("ownerId")}::text from ${calendars} x where x.${k("id")} = ${id})`
        : ""
    };
  end if;`
      : "";

  const visibilityCheck = (key: string, labels: string, hint: string) =>
    `
  if v_item ? '${key}' and v_item ->> '${key}' not in ${labels} then
    ${fail(hint, `visibility must be one of ${labels}`, "22023")}
  end if;`;

  const ownCalendar = ctx.has("calendars", "ownerId")
    ? `create_calendar.owner_id = auth.uid()::text${ctx.has("calendars", "ownerType") ? " and coalesce(create_calendar.owner_type, 'user') = 'user'" : ""}`
    : "false";

  const createAllowed = features.access
    ? `(${allowed("create_calendar.tenant", manage)} or (${ownCalendar} and ${ctx.scope.can("create_calendar.tenant", write)}))`
    : allowed("create_calendar.tenant", manage);

  const tableWrites = features.table
    ? `
  if v_item ? 'rrule' then
    delete from ${ctx.table("rules")} where ${ctx.col("rules", "event")} = v_id;
    if nullif(v_item ->> 'rrule', '') is not null then
      ${insertRule(ctx, "v_id", "v_tenant", "(v_item ->> 'rrule')")}
    end if;
  end if;
  if v_created or v_item ? 'exdates' then
    ${replaceDates(ctx, "v_id", "v_tenant", "exdate", "v_exdates")}
  end if;
  if v_created or v_item ? 'rdates' then
    ${replaceDates(ctx, "v_id", "v_tenant", "rdate", "v_rdates")}
  end if;`
    : "";

  const updateCalendar = attrs
    ? `
-- Changes a calendar's name, tz, color${features.details ? ", description, rank, isDefault" : ""}${features.access ? " and visibility" : ""}:
-- keys left out keep their value.
create or replace function ${fn("update_calendar")}(calendar_id uuid, attrs jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(update_calendar.attrs, '{}'::jsonb);
  v_tenant ${ctx.idType};
  v_name text;
begin
  select ${k("tenant")} into v_tenant from ${calendars} where ${k("id")} = update_calendar.calendar_id;
  if not found then
    ${fail("CALENDAR_NOT_FOUND", "calendar not found", "P0002")}
  end if;
  if not ${features.access ? accessCall(ctx, "update_calendar.calendar_id", "manage") : allowed("v_tenant", manage)} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to manage calendars")}
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names where name = v_item ->> 'tz') then
    ${fail("CALENDAR_TZ_INVALID", "tz must be an IANA time zone", "22023")}
  end if;${features.access ? visibilityCheck("visibility", "('shared', 'private')", "CALENDAR_INVALID") : ""}
  update ${calendars} set ${[
    `${k("name")} = case when v_item ? 'name' then v_item ->> 'name' else ${k("name")} end`,
    `${k("tz")} = case when v_item ? 'tz' then v_item ->> 'tz' else ${k("tz")} end`,
    ...attrColumns.map(
      ([key, column, value]) =>
        `${column} = case when v_item ? '${key}' then ${value} else ${column} end`,
    ),
  ].join(",\n    ")}
  where ${k("id")} = update_calendar.calendar_id
  returning ${k("name")} into v_name;${
    features.access && ctx.has("calendars", "visibility")
      ? `
  if exists (select 1 from ${calendars} k where k.${k("id")} = update_calendar.calendar_id and ${privateCalendar(ctx, "k.")}${ctx.has("calendars", "ownerId") ? ` and k.${k("ownerId")} is null` : ""}) then
    ${fail("CALENDAR_INVALID", "a private calendar needs an owner", "22023")}
  end if;`
      : ""
  }${clearDefault("update_calendar.calendar_id", "v_tenant")}
  ${ctx.record({
    type: "calendar.updated",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', update_calendar.calendar_id, 'name', v_name)`,
    subject: `'calendars/' || update_calendar.calendar_id::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("update_calendar")}(uuid, jsonb)`)}
`
    : "";

  return `${schemaPreamble(ctx)}${accessFunctions(ctx)}
${tables}
${calendarExtras.length === 0 ? "" : `${calendarExtra.drop(fn("create_calendar"), `${ctx.idType}, text, text, text, text`)}\n`}${attrs ? `drop function if exists ${fn("create_calendar")}(${ctx.idType}, text, text, text, text${calendarExtra.type});\n` : ""}create or replace function ${fn("create_calendar")}(tenant ${ctx.idType}, name text, tz text, owner_type text, owner_id text${calendarExtra.param}${attrs ? ", attrs jsonb default null" : ""})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;${attrs ? "\n  v_item jsonb := coalesce(create_calendar.attrs, '{}'::jsonb);" : ""}
begin
  if not ${createAllowed} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to manage calendars")}
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(create_calendar.tz, 'UTC')) then
    ${fail("CALENDAR_TZ_INVALID", "tz must be an IANA time zone", "22023")}
  end if;${
    features.access && ctx.has("calendars", "visibility")
      ? `${visibilityCheck("visibility", "('shared', 'private')", "CALENDAR_INVALID")}
  if v_item ->> 'visibility' = 'private' and create_calendar.owner_id is null then
    ${fail("CALENDAR_INVALID", "a private calendar needs an owner", "22023")}
  end if;`
      : ""
  }
  insert into ${calendars} (${k("tenant")}, ${k("name")}, ${k("tz")}${ctx.has("calendars", "ownerType") ? `, ${k("ownerType")}` : ""}${ctx.has("calendars", "ownerId") ? `, ${k("ownerId")}` : ""}${attrColumns.map(([, column]) => `, ${column}`).join("")}${calendarRequired.columns})
  values (create_calendar.tenant, create_calendar.name, coalesce(create_calendar.tz, 'UTC')${ctx.has("calendars", "ownerType") ? ", create_calendar.owner_type" : ""}${ctx.has("calendars", "ownerId") ? `, ${ctx.cast("calendars", "ownerId", "create_calendar.owner_id")}` : ""}${attrColumns.map(([, , value]) => `, ${value}`).join("")}${calendarRequired.values})
  returning ${k("id")} into v_id;${clearDefault("v_id", "create_calendar.tenant")}${writeExtraColumns(calendars, calendarExtras, "create_calendar.fields", `x.${k("id")} = v_id`)}
  ${ctx.record({
    type: "calendar.created",
    payload: `jsonb_build_object('organizationId', create_calendar.tenant, 'id', v_id, 'name', create_calendar.name)`,
    subject: `'calendars/' || v_id::text`,
    tenant: "create_calendar.tenant",
    audit: false,
  })}
  return jsonb_build_object('id', v_id);
end;
$$;
${userGrant(`${fn("create_calendar")}(${ctx.idType}, text, text, text, text${calendarExtra.type}${attrs ? ", jsonb" : ""})`)}

create or replace function ${fn("delete_calendar")}(calendar_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
begin
  select ${k("tenant")} into v_tenant from ${calendars} where ${k("id")} = delete_calendar.calendar_id;
  if not found then
    ${fail("CALENDAR_NOT_FOUND", "calendar not found", "P0002")}
  end if;
  if not ${features.access ? accessCall(ctx, "delete_calendar.calendar_id", "manage") : allowed("v_tenant", manage)} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to manage calendars")}
  end if;
  delete from ${calendars} where ${k("id")} = delete_calendar.calendar_id;
  return true;
end;
$$;
${userGrant(`${fn("delete_calendar")}(uuid)`)}

-- Inserts an event, or updates the one named by item.id (keys left out keep
-- their value). An item with recurrenceId and originalStart overrides one
-- occurrence of that series and takes the series' uid.
create or replace function ${fn("save_calendar_event")}(calendar_id uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_calendar_event.item, '{}'::jsonb);
  v_tenant ${ctx.idType};
  v_tz text;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
  v_master uuid := nullif(v_item ->> 'recurrenceId', '')::uuid;
  v_uid text := nullif(v_item ->> 'uid', '');
  v_created boolean := false;
  v_exdates timestamptz[];${features.rdates ? "\n  v_rdates timestamptz[];" : ""}
begin
  select ${k("tenant")}, ${k("tz")} into v_tenant, v_tz from ${calendars} where ${k("id")} = save_calendar_event.calendar_id;
  if not found then
    ${fail("CALENDAR_NOT_FOUND", "calendar not found", "P0002")}
  end if;
  if not ${writesCalendar("save_calendar_event.calendar_id", "v_tenant")} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;${
    features.access
      ? `
  if v_id is not null and not ${eventAccessCall(ctx, "v_id", "write")} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this event")}
  end if;${visibilityCheck("visibility", "('public', 'private')", "CALENDAR_EVENT_INVALID")}`
      : ""
  }
  if v_item ? 'status' and v_item ->> 'status' not in ${STATUSES} then
    ${fail("CALENDAR_EVENT_INVALID", "status must be confirmed, tentative or cancelled", "22023")}
  end if;
  if v_item ? 'kind' and v_item ->> 'kind' not in ${EVENT_KINDS} then
    ${fail("CALENDAR_EVENT_INVALID", "kind must be event, out_of_office or focus_time", "22023")}
  end if;
  if v_item ? 'transparency' and v_item ->> 'transparency' not in ${TRANSPARENCIES} then
    ${fail("CALENDAR_EVENT_INVALID", "transparency must be opaque or transparent", "22023")}
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names where name = v_item ->> 'tz') then
    ${fail("CALENDAR_TZ_INVALID", "tz must be an IANA time zone", "22023")}
  end if;
  select coalesce(array_agg(value::timestamptz order by value::timestamptz), '{}')
    into v_exdates from jsonb_array_elements_text(coalesce(v_item -> 'exdates', '[]'::jsonb));${
      features.rdates
        ? `
  select coalesce(array_agg(value::timestamptz order by value::timestamptz), '{}')
    into v_rdates from jsonb_array_elements_text(coalesce(v_item -> 'rdates', '[]'::jsonb));`
        : ""
    }
  ${ctx.hook("before_calendar_event_save", [
    [ctx.idType, "v_tenant"],
    ["uuid", "save_calendar_event.calendar_id"],
    ["jsonb", "v_item"],
  ])}
  if v_id is null then
    if v_master is not null then
      select ${e("uid")} into v_uid from ${events}
        where ${e("id")} = v_master and ${e("calendar")} = save_calendar_event.calendar_id and ${e("recurrence")} is null and ${recurrence.recurring("")};
      if not found or v_item ->> 'originalStart' is null then
        ${fail("CALENDAR_EVENT_INVALID", "an override needs a recurring event and an originalStart", "22023")}
      end if;
    end if;
    if v_item ->> 'startsAt' is null or v_item ->> 'endsAt' is null then
      ${fail("CALENDAR_EVENT_INVALID", "an event needs startsAt and endsAt", "22023")}
    end if;
    v_id := gen_random_uuid();
    v_uid := coalesce(v_uid, v_id::text);
    insert into ${events} (${e("id")}, ${e("tenant")}, ${e("calendar")}, ${e("uid")}, ${e("recurrence")}, ${e("originalStart")}, ${fields.map(([column]) => column).join(", ")}${ctx.has("events", "createdBy") ? `, ${e("createdBy")}` : ""}${features.access && ctx.has("events", "owner") ? `, ${e("owner")}` : ""})
    values (v_id, v_tenant, save_calendar_event.calendar_id, v_uid, v_master, (v_item ->> 'originalStart')::timestamptz, ${fields.map(([, value]) => value).join(", ")}${ctx.has("events", "createdBy") ? ", auth.uid()" : ""}${features.access && ctx.has("events", "owner") ? ", auth.uid()" : ""});
    v_created := true;
  else
    update ${events} set
    ${updateSet(ctx)}
    where ${e("id")} = v_id and ${e("calendar")} = save_calendar_event.calendar_id
    returning ${e("uid")} into v_uid;
    if not found then
      ${fail("CALENDAR_EVENT_NOT_FOUND", "event not found", "P0002")}
    end if;
  end if;${tableWrites}${writeExtraColumns(events, eventExtras(ctx), "v_item", `x.${e("id")} = v_id`)}
  if exists (select 1 from ${events} where ${e("id")} = v_id and ${e("endsAt")} < ${e("startsAt")}) then
    ${fail("CALENDAR_EVENT_INVALID", "endsAt must not be before startsAt", "22023")}
  end if;
  ${reminderRule(ctx, "save")}
  if v_created then
    ${record("calendar_event.created", "v_id", "save_calendar_event.calendar_id", "v_tenant")}
  else
    ${record("calendar_event.updated", "v_id", "save_calendar_event.calendar_id", "v_tenant")}
  end if;
  ${ctx.hook("after_calendar_event_save", [["uuid", "v_id"]])}
  return jsonb_build_object('id', v_id, 'uid', v_uid, 'created', v_created);
end;
$$;
${userGrant(`${fn("save_calendar_event")}(uuid, jsonb)`)}

create or replace function ${fn("delete_calendar_event")}(event_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := delete_calendar_event.event_id;
  v_tenant ${ctx.idType};
  v_calendar uuid;
begin
  select ${e("tenant")}, ${e("calendar")} into v_tenant, v_calendar from ${events} where ${e("id")} = v_id;
  if not found then
    ${fail("CALENDAR_EVENT_NOT_FOUND", "event not found", "P0002")}
  end if;
  if not ${writesEvent("v_id", "v_tenant")} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;
  delete from ${events} where ${e("id")} = v_id;
  ${reminderRule(ctx, "delete")}
  ${record("calendar_event.deleted", "v_id", "v_calendar", "v_tenant")}
  return true;
end;
$$;
${userGrant(`${fn("delete_calendar_event")}(uuid)`)}

-- Removes one occurrence of a series: adds an EXDATE and drops its override.
create or replace function ${fn("cancel_calendar_occurrence")}(event_id uuid, original_start timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := cancel_calendar_occurrence.event_id;
  v_tenant ${ctx.idType};
  v_calendar uuid;
begin
  select ${e("tenant")}, ${e("calendar")} into v_tenant, v_calendar from ${events}
    where ${e("id")} = v_id and ${recurrence.recurring("")} for update;
  if not found then
    ${fail("CALENDAR_EVENT_NOT_FOUND", "recurring event not found", "P0002")}
  end if;
  if not ${writesEvent("v_id", "v_tenant")} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;
  ${
    features.table
      ? `if not (cancel_calendar_occurrence.original_start = any (${recurrence.exdatesOf("v_id")})) then
    ${addDate(ctx, "v_id", "v_tenant", "exdate", "cancel_calendar_occurrence.original_start")}
  end if;
  update ${events} set ${e("updatedAt")} = now()
  where ${e("id")} = v_id;`
      : `update ${events} set ${e("exdates")} = (
      select array_agg(distinct d order by d) from unnest(array_append(${e("exdates")}, cancel_calendar_occurrence.original_start)) d
    ), ${e("updatedAt")} = now()
  where ${e("id")} = v_id;`
  }
  delete from ${events} where ${e("recurrence")} = v_id and ${e("originalStart")} = cancel_calendar_occurrence.original_start;
  ${record("calendar_event.updated", "v_id", "v_calendar", "v_tenant")}
  return true;
end;
$$;
${userGrant(`${fn("cancel_calendar_occurrence")}(uuid, timestamptz)`)}

-- "This and following": the series ends before split_at (before_rrule, which
-- splitRule computes), and item starts a new series from split_at with a new
-- uid. Overrides and EXDATEs from split_at on move to the new series.
create or replace function ${fn("split_calendar_event")}(event_id uuid, split_at timestamptz, before_rrule text, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := split_calendar_event.event_id;
  v_tenant ${ctx.idType};
  v_calendar uuid;
  v_uid text;
  v_starts timestamptz;
  v_exdates timestamptz[];${features.rdates ? "\n  v_rdates timestamptz[];" : ""}
  v_new jsonb;
  v_new_id uuid;
  v_new_uid text;
begin
  select ${e("tenant")}, ${e("calendar")}, ${e("uid")}, ${e("startsAt")}, ${recurrence.exdates("")}${features.rdates ? `, ${recurrence.rdates("")}` : ""}
    into v_tenant, v_calendar, v_uid, v_starts, v_exdates${features.rdates ? ", v_rdates" : ""}
  from ${events} where ${e("id")} = v_id and ${recurrence.recurring("")} for update;
  if not found then
    ${fail("CALENDAR_EVENT_NOT_FOUND", "recurring event not found", "P0002")}
  end if;
  if not ${writesEvent("v_id", "v_tenant")} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;
  if split_calendar_event.split_at <= v_starts or nullif(split_calendar_event.before_rrule, '') is null then
    ${fail("CALENDAR_SPLIT_INVALID", "split at a later occurrence, with the rule that ends the series before it", "22023")}
  end if;
  v_new_uid := v_uid || '-' || to_char(split_calendar_event.split_at at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"');
  ${
    features.table
      ? `delete from ${ctx.table("rules")} where ${ctx.col("rules", "event")} = v_id;
  ${insertRule(ctx, "v_id", "v_tenant", "split_calendar_event.before_rrule")}
  delete from ${ctx.table("recurrenceDates")} where ${ctx.col("recurrenceDates", "event")} = v_id and ${ctx.col("recurrenceDates", "at")} >= split_calendar_event.split_at;
  update ${events} set ${e("updatedAt")} = now()
  where ${e("id")} = v_id;`
      : `update ${events} set ${e("rrule")} = split_calendar_event.before_rrule,
    ${e("exdates")} = coalesce((select array_agg(d order by d) from unnest(v_exdates) d where d < split_calendar_event.split_at), '{}'),${
      features.rdates
        ? `
    ${e("rdates")} = coalesce((select array_agg(d order by d) from unnest(v_rdates) d where d < split_calendar_event.split_at), '{}'),`
        : ""
    }
    ${e("updatedAt")} = now()
  where ${e("id")} = v_id;`
  }
  ${reminderRule(ctx, "save")}
  v_new := ${fn("save_calendar_event")}(v_calendar, (coalesce(split_calendar_event.item, '{}'::jsonb) - 'id' - 'recurrenceId' - 'originalStart') || jsonb_build_object(
    'uid', v_new_uid,
    'exdates', coalesce((select jsonb_agg(d order by d) from unnest(v_exdates) d where d >= split_calendar_event.split_at), '[]'::jsonb)${
      features.rdates
        ? `,
    'rdates', coalesce((select jsonb_agg(d order by d) from unnest(v_rdates) d where d >= split_calendar_event.split_at), '[]'::jsonb)`
        : ""
    }
  ));
  v_new_id := (v_new ->> 'id')::uuid;
  update ${events} set ${e("recurrence")} = v_new_id, ${e("uid")} = v_new_uid, ${e("updatedAt")} = now()
  where ${e("recurrence")} = v_id and ${e("originalStart")} >= split_calendar_event.split_at;
  ${record("calendar_event.updated", "v_id", "v_calendar", "v_tenant")}
  return jsonb_build_object('id', v_new_id, 'uid', v_new_uid);
end;
$$;
${userGrant(`${fn("split_calendar_event")}(uuid, timestamptz, text, jsonb)`)}

-- Upserts source.events, parsed iCalendar events, by uid (and originalStart for overrides).
-- Overrides whose series is not in the calendar are skipped.
create or replace function ${fn("import_calendar_events")}(calendar_id uuid, source jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb;
  v_id uuid;
  v_master uuid;
  v_created integer := 0;
  v_updated integer := 0;
  v_skipped integer := 0;
begin${
    features.access
      ? `
  if not ${accessCall(ctx, "import_calendar_events.calendar_id", "write")} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;`
      : ""
  }
  for v_item in
    select value from jsonb_array_elements(coalesce(import_calendar_events.source -> 'events', '[]'::jsonb))
    order by value ? 'originalStart', value ->> 'uid'
  loop
    v_id := null;
    if v_item ->> 'originalStart' is null then
      select ${e("id")} into v_id from ${events}
        where ${e("calendar")} = import_calendar_events.calendar_id and ${e("uid")} = v_item ->> 'uid' and ${e("originalStart")} is null;
    else
      select ${e("id")} into v_master from ${events}
        where ${e("calendar")} = import_calendar_events.calendar_id and ${e("uid")} = v_item ->> 'uid' and ${e("originalStart")} is null and ${recurrence.recurring("")};
      if v_master is null then
        v_skipped := v_skipped + 1;
        continue;
      end if;
      select ${e("id")} into v_id from ${events}
        where ${e("calendar")} = import_calendar_events.calendar_id and ${e("uid")} = v_item ->> 'uid'
          and ${e("originalStart")} = (v_item ->> 'originalStart')::timestamptz;
      v_item := v_item || jsonb_build_object('recurrenceId', v_master);
    end if;
    if v_id is null then
      perform ${fn("save_calendar_event")}(import_calendar_events.calendar_id, v_item - 'id');
      v_created := v_created + 1;
    else
      perform ${fn("save_calendar_event")}(import_calendar_events.calendar_id, (v_item - 'recurrenceId' - 'originalStart') || jsonb_build_object('id', v_id));
      v_updated := v_updated + 1;
    end if;
  end loop;
  return jsonb_build_object('created', v_created, 'updated', v_updated, 'skipped', v_skipped);
end;
$$;
${userGrant(`${fn("import_calendar_events")}(uuid, jsonb)`)}

-- The events that can fall in [range_start, range_end): single events that
-- overlap it, series that start before its end, and the overrides of those
-- series. occurrences() in TypeScript expands the series. Runs as the
-- caller, so the tables' policies decide what it returns.
create or replace function ${fn("list_calendar_events")}(calendar_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${eventJson(ctx, attendees)} order by e.${e("startsAt")}, e.${e("id")}), '[]'::jsonb)
  from ${events} e
  where e.${e("calendar")} = any (list_calendar_events.calendar_ids)
    and e.${e("startsAt")} < list_calendar_events.range_end
    and (
      (${recurrence.single("e.")} and e.${e("recurrence")} is null and e.${e("endsAt")} > list_calendar_events.range_start)
      or ${recurrence.recurring("e.")}
      or (e.${e("recurrence")} is not null and (e.${e("endsAt")} > list_calendar_events.range_start or e.${e("originalStart")} >= list_calendar_events.range_start - interval '1 year'))
    )
$$;
${userGrant(`${fn("list_calendar_events")}(uuid[], timestamptz, timestamptz)`)}

create or replace function ${fn("list_calendars")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', k.${k("id")}, 'name', k.${k("name")}, 'tz', k.${k("tz")}${ctx.has("calendars", "color") ? `, 'color', k.${k("color")}` : ""}${ctx.has("calendars", "ownerType") ? `, 'ownerType', k.${k("ownerType")}` : ""}${ctx.has("calendars", "ownerId") ? `, 'ownerId', k.${k("ownerId")}` : ""}${
    features.access && ctx.has("calendars", "visibility")
      ? `, 'visibility', ${ctx.label("calendars", "visibility", `k.${k("visibility")}`)}`
      : ""
  }${features.details && ctx.has("calendars", "description") ? `, 'description', k.${k("description")}` : ""}${features.details && ctx.has("calendars", "rank") ? `, 'rank', k.${k("rank")}` : ""}${features.details && ctx.has("calendars", "isDefault") ? `, 'isDefault', k.${k("isDefault")}` : ""}${extraFieldsJson("k", calendarExtras)}) order by ${features.details && ctx.has("calendars", "rank") ? `k.${k("rank")} nulls last, ` : ""}k.${k("name")}), '[]'::jsonb)
  from ${calendars} k
  where k.${k("tenant")} = list_calendars.tenant
$$;
${userGrant(`${fn("list_calendars")}(${ctx.idType})`)}
${updateCalendar}${grantFunctions(ctx)}${attendeeFunctions}${availabilitySql(ctx)}${feed(ctx, events, calendars, attendees)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const features = calendarFeatures(ctx);
  const attrs = features.access || features.details;

  return [
    {
      name: "create_calendar",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "text",
        ...extraFieldsArg(
          ctx.extraColumns("calendars", ["fields"], "calendarExtraColumns"),
        ).contract,
        ...(attrs ? ["jsonb"] : []),
      ],
      returns: "jsonb",
    },
    ...(attrs
      ? [
          {
            name: "update_calendar",
            args: ["uuid", "jsonb"],
            returns: "boolean",
          },
        ]
      : []),
    ...(features.grants
      ? [
          {
            name: "set_calendar_grant",
            args: ["uuid", "uuid", "text"],
            returns: "boolean",
          },
          {
            name: "remove_calendar_grant",
            args: ["uuid", "uuid"],
            returns: "boolean",
          },
          { name: "list_calendar_grants", args: ["uuid"], returns: "jsonb" },
        ]
      : []),
    { name: "delete_calendar", args: ["uuid"], returns: "boolean" },
    { name: "save_calendar_event", args: ["uuid", "jsonb"], returns: "jsonb" },
    { name: "delete_calendar_event", args: ["uuid"], returns: "boolean" },
    {
      name: "cancel_calendar_occurrence",
      args: ["uuid", "timestamptz"],
      returns: "boolean",
    },
    {
      name: "split_calendar_event",
      args: ["uuid", "timestamptz", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "import_calendar_events",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "list_calendar_events",
      args: ["uuid[]", "timestamptz", "timestamptz"],
      returns: "jsonb",
    },
    { name: "list_calendars", args: ["{id}"], returns: "jsonb" },
    ...(ctx.hasTable("attendees")
      ? [
          {
            name: "set_calendar_attendee",
            args: ["uuid", "text", "text", "uuid", "text"],
            returns: "boolean",
          },
          {
            name: "respond_calendar_event",
            args: ["uuid", "text"],
            returns: "boolean",
          },
          ...(features.anyAttendee
            ? [
                {
                  name: "set_calendar_attendee",
                  args: ["uuid", "jsonb"],
                  returns: "jsonb",
                },
                {
                  name: "remove_calendar_attendee",
                  args: ["uuid"],
                  returns: "boolean",
                },
              ]
            : []),
        ]
      : []),
    ...availabilityContract(ctx),
    ...(ctx.installed("share-links")
      ? [{ name: "calendar_feed", args: ["text"], returns: "jsonb" }]
      : []),
    ...(ctx.installed("share-links") && features.userFeed
      ? [{ name: "calendar_user_feed", args: ["text"], returns: "jsonb" }]
      : []),
  ];
}

const CONTRIBUTES: BlockContributes = {
  "share-links": (own) => {
    const features = calendarFeatures(own);
    const read = own.permission("read", moduleOperations("calendar").read);
    const k = (column: string) => `s.${own.col("calendars", column)}`;

    return [
      {
        subject: "calendar",
        exists: (subject) =>
          features.access
            ? `exists (select 1 from ${own.table("calendars")} s where ${k("id")}::text = ${subject.id} and ${k("tenant")}::text = ${subject.tenant}::text and ${accessCall(own, k("id"), "read")})`
            : shareLinkRow(own, "calendars", subject),
      },
      ...(features.userFeed
        ? [
            {
              subject: "calendar_user",
              exists: (subject: {
                readonly id: string;
                readonly tenant: string;
              }) =>
                `(${subject.id} = auth.uid()::text and ${own.scope.can(subject.tenant, read)})`,
            },
          ]
        : []),
    ];
  },
};

export const CALENDAR: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "calendar",
  scopes: ["tenant"],
  title: "Calendar",
  description:
    "Calendars, events with RFC 5545 recurrence (RRULE, EXDATE and per-occurrence overrides) and attendees, working hours, out-of-office and focus-time blocks, and a free/busy query that counts approved leave. Series expand in TypeScript with the reminders block's expandRule and in SQL for free/busy; a share link serves an iCal feed.",
  requires: ["memberships", "permissions"],
  integrates: ["share-links", "reminders", "outbox", "leave"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: CALENDAR_NAMES,
  contract,
  build,
};
