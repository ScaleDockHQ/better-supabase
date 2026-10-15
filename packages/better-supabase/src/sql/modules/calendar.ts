import type { CalendarEvents } from "../../blocks/calendar/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import {
  fail,
  lockTable,
  schemaPreamble,
  sha256Hex,
  userGrant,
} from "../shared.ts";
import { moduleOperations } from "./access-model.ts";

const EVENTS: ModuleEvents<CalendarEvents> = {
  "calendar.created": {
    subject: "calendars",
    payload: ["organizationId", "id", "name"],
  },
  "calendar_event.created": {
    subject: "calendar-events",
    payload: ["organizationId", "id", "calendarId"],
  },
  "calendar_event.updated": {
    subject: "calendar-events",
    payload: ["organizationId", "id", "calendarId"],
  },
  "calendar_event.deleted": {
    subject: "calendar-events",
    payload: ["organizationId", "id", "calendarId"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  hooks: ["before_calendar_event_save", "after_calendar_event_save"],
  options: [],
  tables: {
    calendars: {
      name: "calendars",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        tz: "tz",
        color: "color",
        ownerType: "owner_type",
        ownerId: "owner_id",
        createdAt: "created_at",
      },
      optional: ["color", "ownerType", "ownerId"],
    },
    events: {
      name: "calendar_events",
      lifecycle: {
        tenant: "tenant",
        user: "createdBy",
        purge: false,
        export: true,
      },
      columns: {
        id: "id",
        tenant: "tenant_id",
        calendar: "calendar_id",
        uid: "uid",
        title: "title",
        description: "description",
        location: "location",
        startsAt: "starts_at",
        endsAt: "ends_at",
        allDay: "all_day",
        tz: "tz",
        status: "status",
        rrule: "rrule",
        exdates: "exdates",
        recurrence: "recurrence_id",
        originalStart: "original_start",
        subjectType: "subject_type",
        subjectId: "subject_id",
        color: "color",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "description",
        "location",
        "subjectType",
        "subjectId",
        "color",
        "createdBy",
      ],
    },
    attendees: {
      name: "calendar_attendees",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      optionalTable: true,
      columns: {
        id: "id",
        tenant: "tenant_id",
        event: "event_id",
        email: "email",
        name: "name",
        user: "user_id",
        role: "role",
        response: "response",
      },
    },
  },
};

const STATUSES = "('confirmed', 'tentative', 'cancelled')";
const RESPONSES = "('needs-action', 'accepted', 'declined', 'tentative')";

/** `jsonb -> column` assignments for an insert, for the optional columns that exist. */
function eventFields(
  ctx: ModuleContext,
): readonly (readonly [string, string])[] {
  const e = (column: string) => ctx.col("events", column);
  const fields: [string, string][] = [
    [e("title"), "coalesce(v_item ->> 'title', '')"],
    [e("startsAt"), "(v_item ->> 'startsAt')::timestamptz"],
    [e("endsAt"), "(v_item ->> 'endsAt')::timestamptz"],
    [e("allDay"), "coalesce((v_item ->> 'allDay')::boolean, false)"],
    [e("tz"), "coalesce(v_item ->> 'tz', v_tz)"],
    [e("status"), "coalesce(v_item ->> 'status', 'confirmed')"],
    [e("rrule"), "nullif(v_item ->> 'rrule', '')"],
    [e("exdates"), "v_exdates"],
  ];
  for (const column of ["description", "location", "color"] as const) {
    if (ctx.has("events", column))
      fields.push([e(column), `v_item ->> '${column}'`]);
  }
  if (ctx.has("events", "subjectType") && ctx.has("events", "subjectId")) {
    fields.push(
      [e("subjectType"), "v_item ->> 'subjectType'"],
      [e("subjectId"), "v_item ->> 'subjectId'"],
    );
  }
  return fields;
}

/** An update keeps a column the payload leaves out. */
function updateSet(ctx: ModuleContext): string {
  const keys: Readonly<Record<string, string>> = {
    title: "title",
    startsAt: "startsAt",
    endsAt: "endsAt",
    allDay: "allDay",
    tz: "tz",
    status: "status",
    rrule: "rrule",
    description: "description",
    location: "location",
    color: "color",
    subjectType: "subjectType",
    subjectId: "subjectId",
  };
  const values = new Map(eventFields(ctx));
  const sets: string[] = [];
  for (const [column, key] of Object.entries(keys)) {
    if (!ctx.has("events", column)) continue;
    const ident = ctx.col("events", column);
    const value = values.get(ident);
    if (value === undefined) continue;
    sets.push(
      `${ident} = case when v_item ? '${key}' then ${value} else ${ident} end`,
    );
  }
  const exdates = ctx.col("events", "exdates");
  sets.push(
    `${exdates} = case when v_item ? 'exdates' then v_exdates else ${exdates} end`,
    `${ctx.col("events", "updatedAt")} = now()`,
  );
  return sets.join(",\n    ");
}

/** A jsonb object of one event row, aliased `e`. */
function eventJson(ctx: ModuleContext, attendees: string): string {
  const e = (column: string) => `e.${ctx.col("events", column)}`;
  const optional = (key: string, column: string) =>
    ctx.has("events", column) ? `, '${key}', ${e(column)}` : "";
  const a = (column: string) => `a.${ctx.col("attendees", column)}`;
  const list = ctx.hasTable("attendees")
    ? `, 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', ${a("email")}, 'name', ${a("name")}, 'userId', ${a("user")}, 'role', ${a("role")}, 'response', ${a("response")}) order by ${a("email")}) from ${attendees} a where ${a("event")} = ${e("id")}), '[]'::jsonb)`
    : "";
  return `jsonb_build_object('id', ${e("id")}, 'calendarId', ${e("calendar")}, 'uid', ${e("uid")}, 'title', ${e("title")}, 'startsAt', ${e("startsAt")}, 'endsAt', ${e("endsAt")}, 'allDay', ${e("allDay")}, 'tz', ${e("tz")}, 'status', ${e("status")}, 'rrule', ${e("rrule")}, 'exdates', to_jsonb(${e("exdates")}), 'recurrenceId', ${e("recurrence")}, 'originalStart', ${e("originalStart")}${optional("description", "description")}${optional("location", "location")}${optional("color", "color")}${optional("subjectType", "subjectType")}${optional("subjectId", "subjectId")}) || jsonb_build_object('updatedAt', ${e("updatedAt")}${list})`;
}

/** The reminders rule that mirrors an event, so reminders can attach to it. */
function reminderRule(ctx: ModuleContext, op: "save" | "delete"): string {
  if (!ctx.installed("reminders")) return "";
  const r = ctx.of("reminders");
  if (!r.has("rules", "rrule")) return "";
  const rules = r.table("rules");
  const col = (column: string) => r.col("rules", column);
  if (op === "delete") {
    return `delete from ${rules} where ${col("subjectType")} = 'calendar_event' and ${col("subjectId")} = v_id::text;`;
  }
  return `insert into ${rules} (${col("tenant")}, ${col("subjectType")}, ${col("subjectId")}, ${col("dtstart")}, ${col("tzid")}, ${col("rrule")})
  select e.${ctx.col("events", "tenant")}, 'calendar_event', e.${ctx.col("events", "id")}::text, e.${ctx.col("events", "startsAt")}, e.${ctx.col("events", "tz")}, coalesce(e.${ctx.col("events", "rrule")}, 'FREQ=DAILY;COUNT=1')
  from ${ctx.table("events")} e where e.${ctx.col("events", "id")} = v_id
  on conflict (${col("tenant")}, ${col("subjectType")}, ${col("subjectId")})
  do update set ${col("dtstart")} = excluded.${col("dtstart")}, ${col("tzid")} = excluded.${col("tzid")}, ${col("rrule")} = excluded.${col("rrule")};`;
}

function feed(
  ctx: ModuleContext,
  events: string,
  calendars: string,
  attendees: string,
): string {
  if (!ctx.installed("share-links")) return "";
  const s = ctx.of("share-links");
  const links = s.table("links");
  const l = (column: string) => `l.${s.col("links", column)}`;
  const k = (column: string) => `k.${ctx.col("calendars", column)}`;
  return `
-- The events of the calendar a share link points at, for an iCal feed. Open
-- to anon: the token is the credential, and it is hashed before the lookup.
create or replace function ${ctx.fn("calendar_feed")}(token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_subject text;
  v_tenant text;
  v_calendar uuid;
begin
  if calendar_feed.token is null or length(calendar_feed.token) < 32 then
    return null;
  end if;
  select ${l("subjectId")}, ${l("tenant")}::text into v_subject, v_tenant
  from ${links} l
  where ${l("tokenHash")} = ${sha256Hex("convert_to(calendar_feed.token, 'utf8')")}
    and ${l("subjectType")} = 'calendar'
    and ${l("revokedAt")} is null
    and (${l("expiresAt")} is null or ${l("expiresAt")} > now());
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_calendar := v_subject::uuid;
  return (
    select jsonb_build_object(
      'calendar', jsonb_build_object('id', ${k("id")}, 'name', ${k("name")}, 'tz', ${k("tz")}),
      'events', coalesce((
        select jsonb_agg(${eventJson(ctx, attendees)} order by e.${ctx.col("events", "startsAt")})
        from ${events} e
        where e.${ctx.col("events", "calendar")} = v_calendar
          and (e.${ctx.col("events", "rrule")} is not null or e.${ctx.col("events", "endsAt")} > now() - interval '1 year')
      ), '[]'::jsonb)
    )
    from ${calendars} k where ${k("id")} = v_calendar and ${k("tenant")}::text = v_tenant
  );
end;
$$;
revoke all on function ${ctx.fn("calendar_feed")}(text) from public;
grant execute on function ${ctx.fn("calendar_feed")}(text) to anon, authenticated, service_role;
`;
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
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
  const record = (type: string, id: string, calendar: string, tenant: string) =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${tenant}, 'id', ${id}, 'calendarId', ${calendar})`,
      subject: `'calendar-events/' || ${id}::text`,
      tenant,
      audit: false,
    });
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
);
${lockTable(calendars, { read: true })}
drop policy if exists calendars_read on ${calendars};
create policy calendars_read on ${calendars} for select to authenticated
using (${ctx.scope.check(k("tenant"), read)});
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
  ${e("createdBy")} uuid,
  ${e("createdAt")} timestamptz not null default now(),
  ${e("updatedAt")} timestamptz not null default now(),
  check (${e("endsAt")} >= ${e("startsAt")}),
  check ((${e("recurrence")} is null) = (${e("originalStart")} is null)),
  unique nulls not distinct (${e("calendar")}, ${e("uid")}, ${e("originalStart")})
);
create index if not exists calendar_events_recurrence_idx on ${events} (${e("recurrence")}) where ${e("recurrence")} is not null;
create index if not exists calendar_events_range_idx on ${events} (${e("calendar")}, ${e("startsAt")});
${lockTable(events, { read: true })}
drop policy if exists calendar_events_read on ${events};
create policy calendar_events_read on ${events} for select to authenticated
using (${ctx.scope.check(e("tenant"), read)});
create table if not exists ${attendees} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("event")} uuid not null references ${events} (${e("id")}) on delete cascade,
  ${a("email")} text not null,
  ${a("name")} text,
  ${a("user")} uuid,
  ${a("role")} text not null default 'required',
  ${a("response")} text not null default 'needs-action' check (${a("response")} in ${RESPONSES}),
  unique (${a("event")}, ${a("email")})
);
${lockTable(attendees, { read: true })}
drop policy if exists calendar_attendees_read on ${attendees};
create policy calendar_attendees_read on ${attendees} for select to authenticated
using (${ctx.scope.check(a("tenant"), read)} or ${a("user")} = (select auth.uid()));
`
    : "";
  const attendeeFunctions = ctx.hasTable("attendees")
    ? `
create or replace function ${fn("set_calendar_attendee")}(event_id uuid, email text, name text, user_id uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
begin
  select ${e("tenant")} into v_tenant from ${events} where ${e("id")} = set_calendar_attendee.event_id;
  if not found then
    ${fail("CALENDAR_EVENT_NOT_FOUND", "event not found", "P0002")}
  end if;
  if not ${allowed("v_tenant", write)} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;
  insert into ${attendees} (${a("tenant")}, ${a("event")}, ${a("email")}, ${a("name")}, ${a("user")}, ${a("role")})
  values (v_tenant, set_calendar_attendee.event_id, lower(set_calendar_attendee.email), set_calendar_attendee.name, set_calendar_attendee.user_id, coalesce(set_calendar_attendee.role, 'required'))
  on conflict (${a("event")}, ${a("email")}) do update
    set ${a("name")} = excluded.${a("name")}, ${a("user")} = excluded.${a("user")}, ${a("role")} = excluded.${a("role")};
  return true;
end;
$$;
${userGrant(`${fn("set_calendar_attendee")}(uuid, text, text, uuid, text)`)}

create or replace function ${fn("remove_calendar_attendee")}(event_id uuid, email text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
begin
  select ${e("tenant")} into v_tenant from ${events} where ${e("id")} = remove_calendar_attendee.event_id;
  if not found then
    ${fail("CALENDAR_EVENT_NOT_FOUND", "event not found", "P0002")}
  end if;
  if not ${allowed("v_tenant", write)} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;
  delete from ${attendees} where ${a("event")} = remove_calendar_attendee.event_id and ${a("email")} = lower(remove_calendar_attendee.email);
  return found;
end;
$$;
${userGrant(`${fn("remove_calendar_attendee")}(uuid, text)`)}

-- The caller answers an invitation: the attendee row with their user id,
-- or their email when the row has none.
create or replace function ${fn("respond_calendar_event")}(event_id uuid, response text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if respond_calendar_event.response not in ${RESPONSES} then
    ${fail("CALENDAR_RESPONSE_INVALID", "response must be needs-action, accepted, declined or tentative", "22023")}
  end if;
  update ${attendees} set ${a("response")} = respond_calendar_event.response,
    ${a("user")} = coalesce(${a("user")}, auth.uid())
  where ${a("event")} = respond_calendar_event.event_id
    and (${a("user")} = auth.uid() or (${a("user")} is null and ${a("email")} = lower(auth.email())));
  if not found then
    ${fail("CALENDAR_ATTENDEE_NOT_FOUND", "you are not invited to this event", "P0002")}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("respond_calendar_event")}(uuid, text)`)}
`
    : "";
  return `${schemaPreamble(ctx)}
${tables}
create or replace function ${fn("create_calendar")}(tenant ${ctx.idType}, name text, tz text, owner_type text, owner_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if not ${allowed("create_calendar.tenant", manage)} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to manage calendars")}
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(create_calendar.tz, 'UTC')) then
    ${fail("CALENDAR_TZ_INVALID", "tz must be an IANA time zone", "22023")}
  end if;
  insert into ${calendars} (${k("tenant")}, ${k("name")}, ${k("tz")}${ctx.has("calendars", "ownerType") ? `, ${k("ownerType")}` : ""}${ctx.has("calendars", "ownerId") ? `, ${k("ownerId")}` : ""})
  values (create_calendar.tenant, create_calendar.name, coalesce(create_calendar.tz, 'UTC')${ctx.has("calendars", "ownerType") ? ", create_calendar.owner_type" : ""}${ctx.has("calendars", "ownerId") ? ", create_calendar.owner_id" : ""})
  returning ${k("id")} into v_id;
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
${userGrant(`${fn("create_calendar")}(${ctx.idType}, text, text, text, text)`)}

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
  if not ${allowed("v_tenant", manage)} then
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
  v_exdates timestamptz[];
begin
  select ${k("tenant")}, ${k("tz")} into v_tenant, v_tz from ${calendars} where ${k("id")} = save_calendar_event.calendar_id;
  if not found then
    ${fail("CALENDAR_NOT_FOUND", "calendar not found", "P0002")}
  end if;
  if not ${allowed("v_tenant", write)} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;
  if v_item ? 'status' and v_item ->> 'status' not in ${STATUSES} then
    ${fail("CALENDAR_EVENT_INVALID", "status must be confirmed, tentative or cancelled", "22023")}
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names where name = v_item ->> 'tz') then
    ${fail("CALENDAR_TZ_INVALID", "tz must be an IANA time zone", "22023")}
  end if;
  select coalesce(array_agg(value::timestamptz order by value::timestamptz), '{}')
    into v_exdates from jsonb_array_elements_text(coalesce(v_item -> 'exdates', '[]'::jsonb));
  ${ctx.hook("before_calendar_event_save", [
    [ctx.idType, "v_tenant"],
    ["uuid", "save_calendar_event.calendar_id"],
    ["jsonb", "v_item"],
  ])}
  if v_id is null then
    if v_master is not null then
      select ${e("uid")} into v_uid from ${events}
        where ${e("id")} = v_master and ${e("calendar")} = save_calendar_event.calendar_id and ${e("recurrence")} is null and ${e("rrule")} is not null;
      if not found or v_item ->> 'originalStart' is null then
        ${fail("CALENDAR_EVENT_INVALID", "an override needs a recurring event and an originalStart", "22023")}
      end if;
    end if;
    if v_item ->> 'startsAt' is null or v_item ->> 'endsAt' is null then
      ${fail("CALENDAR_EVENT_INVALID", "an event needs startsAt and endsAt", "22023")}
    end if;
    v_id := gen_random_uuid();
    v_uid := coalesce(v_uid, v_id::text);
    insert into ${events} (${e("id")}, ${e("tenant")}, ${e("calendar")}, ${e("uid")}, ${e("recurrence")}, ${e("originalStart")}, ${fields.map(([column]) => column).join(", ")}${ctx.has("events", "createdBy") ? `, ${e("createdBy")}` : ""})
    values (v_id, v_tenant, save_calendar_event.calendar_id, v_uid, v_master, (v_item ->> 'originalStart')::timestamptz, ${fields.map(([, value]) => value).join(", ")}${ctx.has("events", "createdBy") ? ", auth.uid()" : ""});
    v_created := true;
  else
    update ${events} set
    ${updateSet(ctx)}
    where ${e("id")} = v_id and ${e("calendar")} = save_calendar_event.calendar_id
    returning ${e("uid")} into v_uid;
    if not found then
      ${fail("CALENDAR_EVENT_NOT_FOUND", "event not found", "P0002")}
    end if;
  end if;
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
  if not ${allowed("v_tenant", write)} then
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
    where ${e("id")} = v_id and ${e("rrule")} is not null for update;
  if not found then
    ${fail("CALENDAR_EVENT_NOT_FOUND", "recurring event not found", "P0002")}
  end if;
  if not ${allowed("v_tenant", write)} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;
  update ${events} set ${e("exdates")} = (
      select array_agg(distinct d order by d) from unnest(array_append(${e("exdates")}, cancel_calendar_occurrence.original_start)) d
    ), ${e("updatedAt")} = now()
  where ${e("id")} = v_id;
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
  v_exdates timestamptz[];
  v_new jsonb;
  v_new_id uuid;
  v_new_uid text;
begin
  select ${e("tenant")}, ${e("calendar")}, ${e("uid")}, ${e("startsAt")}, ${e("exdates")}
    into v_tenant, v_calendar, v_uid, v_starts, v_exdates
  from ${events} where ${e("id")} = v_id and ${e("rrule")} is not null for update;
  if not found then
    ${fail("CALENDAR_EVENT_NOT_FOUND", "recurring event not found", "P0002")}
  end if;
  if not ${allowed("v_tenant", write)} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;
  if split_calendar_event.split_at <= v_starts or nullif(split_calendar_event.before_rrule, '') is null then
    ${fail("CALENDAR_SPLIT_INVALID", "split at a later occurrence, with the rule that ends the series before it", "22023")}
  end if;
  v_new_uid := v_uid || '-' || to_char(split_calendar_event.split_at at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"');
  update ${events} set ${e("rrule")} = split_calendar_event.before_rrule,
    ${e("exdates")} = coalesce((select array_agg(d order by d) from unnest(v_exdates) d where d < split_calendar_event.split_at), '{}'),
    ${e("updatedAt")} = now()
  where ${e("id")} = v_id;
  ${reminderRule(ctx, "save")}
  v_new := ${fn("save_calendar_event")}(v_calendar, (coalesce(split_calendar_event.item, '{}'::jsonb) - 'id' - 'recurrenceId' - 'originalStart') || jsonb_build_object(
    'uid', v_new_uid,
    'exdates', coalesce((select jsonb_agg(d order by d) from unnest(v_exdates) d where d >= split_calendar_event.split_at), '[]'::jsonb)
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
begin
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
        where ${e("calendar")} = import_calendar_events.calendar_id and ${e("uid")} = v_item ->> 'uid' and ${e("originalStart")} is null and ${e("rrule")} is not null;
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
      (e.${e("rrule")} is null and e.${e("recurrence")} is null and e.${e("endsAt")} > list_calendar_events.range_start)
      or e.${e("rrule")} is not null
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
  select coalesce(jsonb_agg(jsonb_build_object('id', k.${k("id")}, 'name', k.${k("name")}, 'tz', k.${k("tz")}${ctx.has("calendars", "color") ? `, 'color', k.${k("color")}` : ""}${ctx.has("calendars", "ownerType") ? `, 'ownerType', k.${k("ownerType")}` : ""}${ctx.has("calendars", "ownerId") ? `, 'ownerId', k.${k("ownerId")}` : ""}) order by k.${k("name")}), '[]'::jsonb)
  from ${calendars} k
  where k.${k("tenant")} = list_calendars.tenant
$$;
${userGrant(`${fn("list_calendars")}(${ctx.idType})`)}
${attendeeFunctions}${feed(ctx, events, calendars, attendees)}`;
}

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  return [
    {
      name: "create_calendar",
      args: ["{id}", "text", "text", "text", "text"],
      returns: "jsonb",
    },
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
        ]
      : []),
    ...(ctx.installed("share-links")
      ? [{ name: "calendar_feed", args: ["text"], returns: "jsonb" }]
      : []),
  ];
}

export const CALENDAR: ModuleDefinition = {
  name: "calendar",
  scopes: ["tenant"],
  title: "Calendar",
  description:
    "Calendars, events with RFC 5545 recurrence (RRULE, EXDATE and per-occurrence overrides) and attendees. Series expand in TypeScript with the reminders block's expandRule; a share link serves an iCal feed.",
  requires: ["tenant", "access"],
  integrates: ["share-links", "reminders", "outbox"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
