import type { BlockSqlContext } from "../context.ts";

import { fail, userGrant } from "../shared.ts";
import { calendarFeatures } from "./calendar-features.ts";
import { RESPONSES, ROLES } from "./calendar-rows.ts";

function anyAttendeeFunctions(
  ctx: BlockSqlContext,
  writesEvent: (event: string, tenant: string) => string,
): string {
  const events = ctx.table("events");
  const attendees = ctx.table("attendees");
  const e = (column: string) => ctx.col("events", column);
  const a = (column: string) => ctx.col("attendees", column);
  const fn = (name: string): string => ctx.fn(name);
  const has = (column: string) => ctx.has("attendees", column);
  const subjects = has("subjectType") && has("subjectId");

  const key = [
    `when v_user is not null then x.${a("user")} = v_user`,
    ...(has("email")
      ? [`when v_email is not null then lower(x.${a("email")}) = v_email`]
      : []),
    ...(subjects
      ? [
          `else x.${a("subjectType")} = v_subject_type and x.${a("subjectId")} = v_subject_id`,
        ]
      : ["else false"]),
  ].join(" ");

  const flags =
    "v_item ? 'role' or v_item ? 'organizer' or v_item ? 'optional'";

  const written: (readonly [string, string, string])[] = [
    [a("tenant"), "v_tenant", ""],
    [a("event"), "set_calendar_attendee.event_id", ""],
    [a("user"), "v_user", `coalesce(v_user, ${a("user")})`],
    [a("response"), ctx.cast("attendees", "response", "'needs-action'"), ""],
    ...(has("email")
      ? [[a("email"), "v_email", `coalesce(v_email, ${a("email")})`] as const]
      : []),
    ...(has("name")
      ? [
          [
            a("name"),
            "v_item ->> 'name'",
            `case when v_item ? 'name' then v_item ->> 'name' else ${a("name")} end`,
          ] as const,
        ]
      : []),
    ...(has("role")
      ? [
          [
            a("role"),
            ctx.cast("attendees", "role", "v_role"),
            `case when ${flags} then ${ctx.cast("attendees", "role", "v_role")} else ${a("role")} end`,
          ] as const,
        ]
      : []),
    ...(subjects
      ? [
          [
            a("subjectType"),
            "v_subject_type",
            `coalesce(v_subject_type, ${a("subjectType")})`,
          ] as const,
          [
            a("subjectId"),
            "v_subject_id",
            `coalesce(v_subject_id, ${a("subjectId")})`,
          ] as const,
        ]
      : []),
    ...(has("organizer")
      ? [
          [
            a("organizer"),
            "coalesce((v_item ->> 'organizer')::boolean, v_role = 'chair')",
            `case when ${flags} then coalesce((v_item ->> 'organizer')::boolean, v_role = 'chair') else ${a("organizer")} end`,
          ] as const,
        ]
      : []),
    ...(has("optional")
      ? [
          [
            a("optional"),
            "coalesce((v_item ->> 'optional')::boolean, v_role = 'optional')",
            `case when ${flags} then coalesce((v_item ->> 'optional')::boolean, v_role = 'optional') else ${a("optional")} end`,
          ] as const,
        ]
      : []),
  ];

  const updates = written.filter(([, , update]) => update !== "");

  const mine = has("email")
    ? `(${a("user")} = auth.uid() or (${a("user")} is null and ${a("email")} = lower(auth.email())))`
    : `${a("user")} = auth.uid()`;

  const byEmail = has("email")
    ? `
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
  if not ${writesEvent("remove_calendar_attendee.event_id", "v_tenant")} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;
  delete from ${attendees} where ${a("event")} = remove_calendar_attendee.event_id and lower(${a("email")}) = lower(remove_calendar_attendee.email);
  return found;
end;
$$;
${userGrant(`${fn("remove_calendar_attendee")}(uuid, text)`)}
`
    : "";

  return `
-- Adds or changes an attendee of an event, found by userId, else email, else
-- subjectType and subjectId: { email, name, userId, role, subjectType,
-- subjectId, organizer, optional }. Returns { id, created }.
create or replace function ${fn("set_calendar_attendee")}(event_id uuid, attendee jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(set_calendar_attendee.attendee, '{}'::jsonb);
  v_tenant ${ctx.idType};
  v_user uuid := nullif(v_item ->> 'userId', '')::uuid;
  v_email text := lower(nullif(v_item ->> 'email', ''));
  v_subject_type text := nullif(v_item ->> 'subjectType', '');
  v_subject_id text := nullif(v_item ->> 'subjectId', '');
  v_role text := coalesce(nullif(v_item ->> 'role', ''), case when (v_item ->> 'organizer')::boolean then 'chair' when (v_item ->> 'optional')::boolean then 'optional' else 'required' end);
  v_id uuid;
begin
  if v_role not in ${ROLES} then
    ${fail("CALENDAR_ROLE_INVALID", "role must be chair, required, optional or non-participant", "22023")}
  end if;
  if v_user is null and ${has("email") ? "v_email is null" : "true"} and ${subjects ? "(v_subject_type is null or v_subject_id is null)" : "true"} then
    ${fail("CALENDAR_ATTENDEE_INVALID", "an attendee needs a userId, an email or a subjectType and subjectId", "22023")}
  end if;
  select ${e("tenant")} into v_tenant from ${events} where ${e("id")} = set_calendar_attendee.event_id;
  if not found then
    ${fail("CALENDAR_EVENT_NOT_FOUND", "event not found", "P0002")}
  end if;
  if not ${writesEvent("set_calendar_attendee.event_id", "v_tenant")} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;
  select x.${a("id")} into v_id from ${attendees} x
  where x.${a("event")} = set_calendar_attendee.event_id and case ${key} end
  limit 1
  for update;
  if v_id is null then
    insert into ${attendees} (${written.map(([column]) => column).join(", ")})
    values (${written.map(([, value]) => value).join(", ")})
    returning ${a("id")} into v_id;
    return jsonb_build_object('id', v_id, 'created', true);
  end if;
  update ${attendees} set ${updates.map(([column, , update]) => `${column} = ${update}`).join(", ")}
  where ${a("id")} = v_id;
  return jsonb_build_object('id', v_id, 'created', false);
end;
$$;
${userGrant(`${fn("set_calendar_attendee")}(uuid, jsonb)`)}

create or replace function ${fn("set_calendar_attendee")}(event_id uuid, email text, name text, user_id uuid, role text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform ${fn("set_calendar_attendee")}(set_calendar_attendee.event_id, jsonb_strip_nulls(jsonb_build_object(
    'email', set_calendar_attendee.email,
    'name', set_calendar_attendee.name,
    'userId', set_calendar_attendee.user_id,
    'role', set_calendar_attendee.role
  )));
  return true;
end;
$$;
${userGrant(`${fn("set_calendar_attendee")}(uuid, text, text, uuid, text)`)}
${byEmail}
create or replace function ${fn("remove_calendar_attendee")}(attendee_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType};
  v_event uuid;
begin
  select x.${e("tenant")}, x.${e("id")} into v_tenant, v_event
  from ${attendees} t
  join ${events} x on x.${e("id")} = t.${a("event")}
  where t.${a("id")} = remove_calendar_attendee.attendee_id;
  if not found then
    ${fail("CALENDAR_ATTENDEE_NOT_FOUND", "attendee not found", "P0002")}
  end if;
  if not ${writesEvent("v_event", "v_tenant")} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;
  delete from ${attendees} where ${a("id")} = remove_calendar_attendee.attendee_id;
  return found;
end;
$$;
${userGrant(`${fn("remove_calendar_attendee")}(uuid)`)}

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
  update ${attendees} set ${a("response")} = ${ctx.cast("attendees", "response", "respond_calendar_event.response")},
    ${a("user")} = coalesce(${a("user")}, auth.uid())
  where ${a("event")} = respond_calendar_event.event_id
    and ${mine};
  if not found then
    ${fail("CALENDAR_ATTENDEE_NOT_FOUND", "you are not invited to this event", "P0002")}
  end if;
  return true;
end;
$$;
${userGrant(`${fn("respond_calendar_event")}(uuid, text)`)}
`;
}

export function attendeesSql(
  ctx: BlockSqlContext,
  writesEvent: (event: string, tenant: string) => string,
): string {
  if (!ctx.hasTable("attendees")) {
    return "";
  }

  if (calendarFeatures(ctx).anyAttendee) {
    return anyAttendeeFunctions(ctx, writesEvent);
  }

  const events = ctx.table("events");
  const attendees = ctx.table("attendees");
  const e = (column: string) => ctx.col("events", column);
  const a = (column: string) => ctx.col("attendees", column);
  const fn = (name: string): string => ctx.fn(name);

  return `
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
  if coalesce(set_calendar_attendee.role, 'required') not in ${ROLES} then
    ${fail("CALENDAR_ROLE_INVALID", "role must be chair, required, optional or non-participant", "22023")}
  end if;
  select ${e("tenant")} into v_tenant from ${events} where ${e("id")} = set_calendar_attendee.event_id;
  if not found then
    ${fail("CALENDAR_EVENT_NOT_FOUND", "event not found", "P0002")}
  end if;
  if not ${writesEvent("set_calendar_attendee.event_id", "v_tenant")} then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to change this calendar")}
  end if;
  insert into ${attendees} (${a("tenant")}, ${a("event")}, ${a("email")}, ${a("name")}, ${a("user")}, ${a("role")})
  values (v_tenant, set_calendar_attendee.event_id, lower(set_calendar_attendee.email), set_calendar_attendee.name, set_calendar_attendee.user_id, ${ctx.cast("attendees", "role", "coalesce(set_calendar_attendee.role, 'required')")})
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
  if not ${writesEvent("remove_calendar_attendee.event_id", "v_tenant")} then
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
  update ${attendees} set ${a("response")} = ${ctx.cast("attendees", "response", "respond_calendar_event.response")},
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
`;
}
