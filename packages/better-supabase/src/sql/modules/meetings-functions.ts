import type { BlockSqlContext } from "../context.ts";
import type { MeetingsSql } from "./meetings-sql.ts";

import { fail, serviceGrant, userGrant } from "../shared.ts";
import { managed, meetingsSql } from "./meetings-sql.ts";
import {
  MEETING_ATTENDANCE,
  MEETING_ATTENDEE_ROLES,
  MEETING_DECISION_STATUSES,
  MEETING_AGENDA_STATUSES,
} from "./meetings-values.ts";

const UUID =
  "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$";

const quoted = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

/** Loads `v_row` by `func.<arg>` for the callers who may see it. */
function load(q: MeetingsSql, func: string, arg: string): string {
  const { m, meetings } = q;

  return `select * into v_row from ${meetings} x where x.${m("id")} = ${func}.${arg} for update;
  if not found or not ${q.sees(`v_row.${m("tenant")}`, `v_row.${m("id")}`)} then
    ${q.missing}
  end if;`;
}

/** The attendee writer: replaces who is invited to a meeting. */
function attendeeWriter(ctx: BlockSqlContext, q: MeetingsSql): string {
  const { fn, a, attendees } = q;
  const ms = ctx.of("memberships");

  return `
-- Replaces the attendees of a meeting with team, [{ userId, role, attendance }].
-- Every attendee belongs to the organization and one at most chairs. The other
-- functions call it; it is not an entry point.
create or replace function ${fn("meeting_set_attendees")}(meeting_id uuid, tenant ${ctx.idType}, team jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_team jsonb := coalesce(meeting_set_attendees.team, '[]'::jsonb);
begin
  if jsonb_typeof(v_team) is distinct from 'array' then
    ${q.invalid("attendees must be a list")}
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'userId', '') !~ '${UUID}'
      or coalesce(e ->> 'role', 'attendee') not in (${quoted(MEETING_ATTENDEE_ROLES)})
      or coalesce(e ->> 'attendance', 'invited') not in (${quoted(MEETING_ATTENDANCE)})
  ) then
    ${q.invalid("each attendee needs a userId, a role of chair, secretary, attendee or guest, and an attendance of invited, present, absent or excused")}
  end if;
  if (select count(distinct e ->> 'userId') from jsonb_array_elements(v_team) e) <> jsonb_array_length(v_team) then
    ${q.invalid("a user is listed twice")}
  end if;
  if (select count(*) from jsonb_array_elements(v_team) e where e ->> 'role' = 'chair') > 1 then
    ${q.invalid("a meeting has one chair")}
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where not exists (
      select 1 from ${ms.table("memberships")} y
      where y.${ms.col("memberships", "tenant")} = meeting_set_attendees.tenant
        and y.${ms.col("memberships", "user")} = (e ->> 'userId')::uuid
    )
  ) then
    ${q.invalid("every attendee must belong to the organization")}
  end if;
  delete from ${attendees} x where x.${a("meeting")} = meeting_set_attendees.meeting_id;
  insert into ${attendees} (${a("meeting")}, ${a("tenant")}, ${a("user")}, ${a("role")}, ${a("attendance")})
  select meeting_set_attendees.meeting_id, meeting_set_attendees.tenant, (e ->> 'userId')::uuid,
    coalesce(e ->> 'role', 'attendee'), coalesce(e ->> 'attendance', 'invited')
  from jsonb_array_elements(v_team) e;
end;
$$;
${serviceGrant(`${fn("meeting_set_attendees")}(uuid, ${ctx.idType}, jsonb)`)}
`;
}

/** Create, update and the status changes. */
function meetingFunctionsSql(ctx: BlockSqlContext, q: MeetingsSql): string {
  const { fn, m, g, meetings, agenda, meetingJson } = q;
  const idType = ctx.idType;
  const has = (column: string): boolean => ctx.has("meetings", column);

  const text = (column: string, max: number, src: string): string =>
    has(column)
      ? `
  if length(${src} ->> '${column}') > ${String(max)} then
    ${q.invalid(`${column} is at most ${String(max)} characters`)}
  end if;`
      : `
  if nullif(trim(${src} ->> '${column}'), '') is not null then
    ${q.invalid(`the meetings table has no ${column} column`)}
  end if;`;

  const checks = (
    src: string,
  ): string => `if v_kind is null or not (v_kind = any (${q.kinds})) then
    ${fail("MEETING_KIND_UNKNOWN", "the kind is not one of options.kinds", "22023")}
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    ${q.invalid("a meeting needs a title of 1 to 300 characters")}
  end if;
  if v_starts is null then
    ${q.invalid("a meeting needs a start time")}
  end if;
  if v_ends < v_starts then
    ${q.invalid("endsAt is on or after startsAt")}
  end if;${text("location", 500, src)}${text("summary", 20_000, src)}`;

  const parse = (
    src: string,
    fallback: (column: string) => string,
  ): string => `begin
    v_kind := coalesce(nullif(trim(${src} ->> 'kind'), ''), ${fallback("kind")});
    v_title := ${src.includes("changes") ? `case when ${src} ? 'title' then trim(${src} ->> 'title') else ${fallback("title")} end` : `trim(${src} ->> 'title')`};
    v_starts := ${src.includes("changes") ? `case when ${src} ? 'startsAt' then (${src} ->> 'startsAt')::timestamptz else ${fallback("startsAt")} end` : `(${src} ->> 'startsAt')::timestamptz`};
    v_ends := ${src.includes("changes") ? `case when ${src} ? 'endsAt' then (${src} ->> 'endsAt')::timestamptz else ${fallback("endsAt")} end` : `(${src} ->> 'endsAt')::timestamptz`};
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    ${q.invalid("startsAt and endsAt are timestamps")}
  end;`;

  const optional = (column: string): string =>
    has(column) ? `, ${m(column)}` : "";

  const optionalValue = (column: string, src: string): string =>
    has(column) ? `, nullif(trim(${src} ->> '${column}'), '')` : "";

  const forbidTransition = (to: string): string => q.statusInvalid("v_row", to);

  return `
-- Plans a meeting. input is { kind, title, location, startsAt, endsAt,
-- attendees: [{ userId, role, attendance }], agenda: [{ title, notes,
-- presenterId }] }. It starts planned. Needs meetings.write.
create or replace function ${fn("create_meeting")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
  v_kind text;
  v_title text;
  v_starts timestamptz;
  v_ends timestamptz;
begin
  if not ${q.allowed("create_meeting.tenant", q.write)} then
    ${q.forbidden("not allowed to plan meetings")}
  end if;
  if jsonb_typeof(create_meeting.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  ${parse("create_meeting.input", (column) => (column === "kind" ? `(${q.kinds})[1]` : "null"))}
  ${checks("create_meeting.input")}
  if create_meeting.input ? 'agenda' and jsonb_typeof(create_meeting.input -> 'agenda') is distinct from 'array' then
    ${q.invalid("agenda must be a list")}
  end if;
  ${ctx.hook("before_meeting_create", [
    [idType, "create_meeting.tenant"],
    ["jsonb", "create_meeting.input"],
  ])}
  insert into ${meetings} (${m("tenant")}, ${m("kind")}, ${m("title")}, ${m("startsAt")}, ${m("endsAt")}${optional("location")}${optional("summary")}${optional("createdBy")})
  values (create_meeting.tenant, v_kind, v_title, v_starts, v_ends${optionalValue("location", "create_meeting.input")}${optionalValue("summary", "create_meeting.input")}${has("createdBy") ? ", auth.uid()" : ""})
  returning * into v_row;
  perform ${fn("meeting_set_attendees")}(v_row.${m("id")}, v_row.${m("tenant")}, create_meeting.input -> 'attendees');
  insert into ${agenda} (${g("tenant")}, ${g("meeting")}, ${g("ordinal")}, ${g("title")}${ctx.has("agenda", "notes") ? `, ${g("notes")}` : ""}, ${g("presenter")})
  select v_row.${m("tenant")}, v_row.${m("id")}, e.n, trim(e.value ->> 'title')${ctx.has("agenda", "notes") ? ", nullif(trim(e.value ->> 'notes'), '')" : ""}, nullif(e.value ->> 'presenterId', '')::uuid
  from jsonb_array_elements(coalesce(create_meeting.input -> 'agenda', '[]'::jsonb)) with ordinality as e(value, n);
  ${q.record("meeting.created", "v_row", "meeting planned")}
  ${ctx.hook("after_meeting_create", [["uuid", `v_row.${m("id")}`]])}
  return ${meetingJson("v_row")};
exception when check_violation or invalid_text_representation or not_null_violation then
  ${q.invalid("an attendee or an agenda item has an invalid value")}
end;
$$;
${userGrant(`${fn("create_meeting")}(${idType}, jsonb)`)}

-- Changes a meeting: the keys of create_meeting except attendees and agenda,
-- and summary. A cancelled meeting takes no changes. Needs meetings.manage, or
-- meetings.write as its creator, chair or secretary.
create or replace function ${fn("update_meeting")}(meeting_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
  v_kind text;
  v_title text;
  v_starts timestamptz;
  v_ends timestamptz;
begin
  ${load(q, "update_meeting", "meeting_id")}
  if not ${q.runs("v_row")} then
    ${q.forbidden("not allowed to change this meeting")}
  end if;
  if v_row.${m("status")} = 'cancelled' then
    ${q.invalid("a cancelled meeting takes no changes")}
  end if;
  if jsonb_typeof(update_meeting.changes) is distinct from 'object' then
    ${q.invalid("changes must be an object")}
  end if;
  ${parse("update_meeting.changes", (column) => `v_row.${m(column)}`)}
  ${checks("update_meeting.changes")}
  update ${meetings} x set
    ${m("kind")} = v_kind,
    ${m("title")} = v_title,${has("location") ? `\n    ${m("location")} = case when update_meeting.changes ? 'location' then nullif(trim(update_meeting.changes ->> 'location'), '') else x.${m("location")} end,` : ""}${has("summary") ? `\n    ${m("summary")} = case when update_meeting.changes ? 'summary' then nullif(trim(update_meeting.changes ->> 'summary'), '') else x.${m("summary")} end,` : ""}
    ${m("startsAt")} = v_starts,
    ${m("endsAt")} = v_ends,
    ${m("updatedAt")} = now()
  where x.${m("id")} = v_row.${m("id")}
  returning * into v_row;
  ${q.record("meeting.updated", "v_row", "meeting updated")}
  return ${meetingJson("v_row")};
end;
$$;
${userGrant(`${fn("update_meeting")}(uuid, jsonb)`)}

-- Opens a planned meeting.
create or replace function ${fn("start_meeting")}(meeting_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
begin
  ${load(q, "start_meeting", "meeting_id")}
  if not ${q.runs("v_row")} then
    ${q.forbidden("not allowed to start this meeting")}
  end if;
  if v_row.${m("status")} <> 'planned' then
    ${forbidTransition("in_progress")}
  end if;
  update ${meetings} x set ${m("status")} = 'in_progress', ${m("startedAt")} = now(), ${m("updatedAt")} = now()
  where x.${m("id")} = v_row.${m("id")}
  returning * into v_row;
  ${q.record("meeting.started", "v_row", "meeting started")}
  return ${meetingJson("v_row")};
end;
$$;
${userGrant(`${fn("start_meeting")}(uuid)`)}

-- Closes a meeting as held, with an optional summary. Every proposed
-- decision stays proposed until someone decides it.
create or replace function ${fn("hold_meeting")}(meeting_id uuid, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
begin
  ${load(q, "hold_meeting", "meeting_id")}
  if not ${q.runs("v_row")} then
    ${q.forbidden("not allowed to close this meeting")}
  end if;
  if v_row.${m("status")} not in ('planned', 'in_progress') then
    ${forbidTransition("held")}
  end if;${
    has("summary")
      ? `
  if length(hold_meeting.summary) > 20000 then
    ${q.invalid("summary is at most 20000 characters")}
  end if;`
      : `
  if nullif(trim(hold_meeting.summary), '') is not null then
    ${q.invalid("the meetings table has no summary column")}
  end if;`
  }
  ${ctx.hook("before_meeting_hold", [["uuid", `v_row.${m("id")}`]])}
  update ${meetings} x set
    ${m("status")} = 'held',
    ${m("startedAt")} = coalesce(x.${m("startedAt")}, now()),
    ${m("heldAt")} = now(),${has("summary") ? `\n    ${m("summary")} = coalesce(nullif(trim(hold_meeting.summary), ''), x.${m("summary")}),` : ""}
    ${m("updatedAt")} = now()
  where x.${m("id")} = v_row.${m("id")}
  returning * into v_row;
  ${q.record("meeting.concluded", "v_row", "meeting held")}
  ${ctx.hook("after_meeting_hold", [["uuid", `v_row.${m("id")}`]])}
  return ${meetingJson("v_row")};
end;
$$;
${userGrant(`${fn("hold_meeting")}(uuid, text)`)}

-- Cancels a meeting that was not held.
create or replace function ${fn("cancel_meeting")}(meeting_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
begin
  ${load(q, "cancel_meeting", "meeting_id")}
  if not ${q.runs("v_row")} then
    ${q.forbidden("not allowed to cancel this meeting")}
  end if;
  if v_row.${m("status")} in ('held', 'cancelled') then
    ${forbidTransition("cancelled")}
  end if;
  if length(cancel_meeting.reason) > 4000 then
    ${q.invalid("reason is at most 4000 characters")}
  end if;
  update ${meetings} x set ${m("status")} = 'cancelled', ${m("updatedAt")} = now()
  where x.${m("id")} = v_row.${m("id")}
  returning * into v_row;
  ${q.record("meeting.cancelled", "v_row", "meeting cancelled", ", 'reason', nullif(trim(cancel_meeting.reason), '')")}
  return ${meetingJson("v_row")};
end;
$$;
${userGrant(`${fn("cancel_meeting")}(uuid, text)`)}

-- Deletes a meeting that is planned or cancelled, with its agenda and
-- decisions. Tasks opened from it stay in the tasks block.
create or replace function ${fn("delete_meeting")}(meeting_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
begin
  ${load(q, "delete_meeting", "meeting_id")}
  if not ${q.runs("v_row")} then
    ${q.forbidden("not allowed to delete this meeting")}
  end if;
  if v_row.${m("status")} not in ('planned', 'cancelled') then
    ${q.invalid("only a planned or cancelled meeting can be deleted")}
  end if;
  delete from ${meetings} x where x.${m("id")} = v_row.${m("id")};
  ${q.record("meeting.deleted", "v_row", "meeting deleted")}
  return ${meetingJson("v_row")};
end;
$$;
${userGrant(`${fn("delete_meeting")}(uuid)`)}
`;
}

function attendeeFunctions(ctx: BlockSqlContext, q: MeetingsSql): string {
  const { fn, m, a, meetings, attendees, attendeeJson } = q;
  const ms = ctx.of("memberships");

  return `
-- Invites a user to a meeting, or changes their role or attendance. A new
-- chair replaces the old one, who becomes an attendee.
create or replace function ${fn("set_meeting_attendee")}(meeting_id uuid, user_id uuid, role text default 'attendee', attendance text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
  v_attendee ${attendees};
begin
  ${load(q, "set_meeting_attendee", "meeting_id")}
  if not ${q.runs("v_row")} then
    ${q.forbidden("not allowed to change who attends this meeting")}
  end if;
  if v_row.${m("status")} = 'cancelled' then
    ${q.invalid("a cancelled meeting takes no changes")}
  end if;
  if set_meeting_attendee.role not in (${quoted(MEETING_ATTENDEE_ROLES)})
    or set_meeting_attendee.attendance not in (${quoted(MEETING_ATTENDANCE)}) then
    ${q.invalid("role or attendance is not one of the allowed values")}
  end if;
  if not exists (
    select 1 from ${ms.table("memberships")} y
    where y.${ms.col("memberships", "tenant")} = v_row.${m("tenant")} and y.${ms.col("memberships", "user")} = set_meeting_attendee.user_id
  ) then
    ${q.invalid("the attendee must belong to the organization")}
  end if;
  if set_meeting_attendee.role = 'chair' then
    update ${attendees} x set ${a("role")} = 'attendee'
    where x.${a("meeting")} = v_row.${m("id")} and x.${a("role")} = 'chair' and x.${a("user")} <> set_meeting_attendee.user_id;
  end if;
  update ${attendees} x set
    ${a("role")} = set_meeting_attendee.role,
    ${a("attendance")} = coalesce(set_meeting_attendee.attendance, x.${a("attendance")})
  where x.${a("meeting")} = v_row.${m("id")} and x.${a("user")} = set_meeting_attendee.user_id
  returning * into v_attendee;
  if not found then
    insert into ${attendees} (${a("meeting")}, ${a("tenant")}, ${a("user")}, ${a("role")}, ${a("attendance")})
    values (v_row.${m("id")}, v_row.${m("tenant")}, set_meeting_attendee.user_id, set_meeting_attendee.role, coalesce(set_meeting_attendee.attendance, 'invited'))
    returning * into v_attendee;
  end if;
  return ${attendeeJson("v_attendee")};
end;
$$;
${userGrant(`${fn("set_meeting_attendee")}(uuid, uuid, text, text)`)}

-- Removes a user from a meeting.
create or replace function ${fn("remove_meeting_attendee")}(meeting_id uuid, user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
  v_attendee ${attendees};
begin
  ${load(q, "remove_meeting_attendee", "meeting_id")}
  if not ${q.runs("v_row")} then
    ${q.forbidden("not allowed to change who attends this meeting")}
  end if;
  delete from ${attendees} x
  where x.${a("meeting")} = v_row.${m("id")} and x.${a("user")} = remove_meeting_attendee.user_id
  returning * into v_attendee;
  if not found then
    ${fail("MEETING_ATTENDEE_NOT_FOUND", "that user is not an attendee", "P0002")}
  end if;
  return ${attendeeJson("v_attendee")};
end;
$$;
${userGrant(`${fn("remove_meeting_attendee")}(uuid, uuid)`)}
`;
}

function agendaFunctions(ctx: BlockSqlContext, q: MeetingsSql): string {
  const { fn, m, g, meetings, agenda, agendaJson } = q;
  const hasNotes = ctx.has("agenda", "notes");
  const hasOutcome = ctx.has("agenda", "outcome");

  return `
-- Adds an agenda item, or with item.id changes one. item is { id, title,
-- notes, presenterId, minutes, status, outcome, ordinal }. Without an ordinal
-- a new item goes last; with one, the items from there move down.
create or replace function ${fn("save_meeting_agenda_item")}(meeting_id uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
  v_item ${agenda};
  v_id uuid;
  v_ordinal integer;
  v_status text;
begin
  ${load(q, "save_meeting_agenda_item", "meeting_id")}
  if not ${q.runs("v_row")} then
    ${q.forbidden("not allowed to change this agenda")}
  end if;
  if v_row.${m("status")} = 'cancelled' then
    ${q.invalid("a cancelled meeting takes no changes")}
  end if;
  if jsonb_typeof(save_meeting_agenda_item.item) is distinct from 'object' then
    ${q.invalid("item must be an object")}
  end if;
  begin
    v_id := nullif(save_meeting_agenda_item.item ->> 'id', '')::uuid;
    v_ordinal := (save_meeting_agenda_item.item ->> 'ordinal')::integer;
  exception when invalid_text_representation then
    ${q.invalid("id is a uuid and ordinal an integer")}
  end;
  v_status := save_meeting_agenda_item.item ->> 'status';
  if v_status is not null and v_status not in (${quoted(MEETING_AGENDA_STATUSES)}) then
    ${q.invalid("status is open, covered or skipped")}
  end if;
  if v_ordinal is not null and v_ordinal < 1 then
    ${q.invalid("ordinal starts at 1")}
  end if;
  if length(save_meeting_agenda_item.item ->> 'minutes') > 50000 then
    ${q.invalid("minutes is at most 50000 characters")}
  end if;
  if v_id is null then
    if coalesce(length(trim(save_meeting_agenda_item.item ->> 'title')), 0) not between 1 and 300 then
      ${q.invalid("an agenda item needs a title of 1 to 300 characters")}
    end if;
    v_ordinal := coalesce(v_ordinal, (select coalesce(max(y.${g("ordinal")}), 0) + 1 from ${agenda} y where y.${g("meeting")} = v_row.${m("id")}));
    update ${agenda} y set ${g("ordinal")} = y.${g("ordinal")} + 1
    where y.${g("meeting")} = v_row.${m("id")} and y.${g("ordinal")} >= v_ordinal;
    insert into ${agenda} (${g("tenant")}, ${g("meeting")}, ${g("ordinal")}, ${g("title")}${hasNotes ? `, ${g("notes")}` : ""}, ${g("presenter")}, ${g("minutes")}, ${g("status")}${hasOutcome ? `, ${g("outcome")}` : ""})
    values (v_row.${m("tenant")}, v_row.${m("id")}, v_ordinal, trim(save_meeting_agenda_item.item ->> 'title')${hasNotes ? ", nullif(trim(save_meeting_agenda_item.item ->> 'notes'), '')" : ""},
      nullif(save_meeting_agenda_item.item ->> 'presenterId', '')::uuid, nullif(save_meeting_agenda_item.item ->> 'minutes', ''), coalesce(v_status, 'open')${hasOutcome ? ", nullif(trim(save_meeting_agenda_item.item ->> 'outcome'), '')" : ""})
    returning * into v_item;
  else
    select * into v_item from ${agenda} y where y.${g("id")} = v_id and y.${g("meeting")} = v_row.${m("id")} for update;
    if not found then
      ${q.agendaMissing}
    end if;
    if v_ordinal is not null and v_ordinal <> v_item.${g("ordinal")} then
      update ${agenda} y set ${g("ordinal")} = y.${g("ordinal")} + 1
      where y.${g("meeting")} = v_row.${m("id")} and y.${g("ordinal")} >= v_ordinal and y.${g("id")} <> v_item.${g("id")};
    end if;
    update ${agenda} y set
      ${g("ordinal")} = coalesce(v_ordinal, y.${g("ordinal")}),
      ${g("title")} = case when save_meeting_agenda_item.item ? 'title' then trim(save_meeting_agenda_item.item ->> 'title') else y.${g("title")} end,${hasNotes ? `\n      ${g("notes")} = case when save_meeting_agenda_item.item ? 'notes' then nullif(trim(save_meeting_agenda_item.item ->> 'notes'), '') else y.${g("notes")} end,` : ""}
      ${g("presenter")} = case when save_meeting_agenda_item.item ? 'presenterId' then nullif(save_meeting_agenda_item.item ->> 'presenterId', '')::uuid else y.${g("presenter")} end,
      ${g("minutes")} = case when save_meeting_agenda_item.item ? 'minutes' then nullif(save_meeting_agenda_item.item ->> 'minutes', '') else y.${g("minutes")} end,
      ${g("status")} = coalesce(v_status, y.${g("status")})${hasOutcome ? `,\n      ${g("outcome")} = case when save_meeting_agenda_item.item ? 'outcome' then nullif(trim(save_meeting_agenda_item.item ->> 'outcome'), '') else y.${g("outcome")} end` : ""}
    where y.${g("id")} = v_item.${g("id")}
    returning * into v_item;
  end if;
  if coalesce(length(v_item.${g("title")}), 0) not between 1 and 300 then
    ${q.invalid("an agenda item needs a title of 1 to 300 characters")}
  end if;
  update ${meetings} x set ${m("updatedAt")} = now() where x.${m("id")} = v_row.${m("id")};
  return ${agendaJson("v_item")};
end;
$$;
${userGrant(`${fn("save_meeting_agenda_item")}(uuid, jsonb)`)}

-- Removes an agenda item and closes the gap in the numbering. Decisions and
-- tasks that named it keep existing without it.
create or replace function ${fn("delete_meeting_agenda_item")}(item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
  v_item ${agenda};
begin
  select * into v_item from ${agenda} y where y.${g("id")} = delete_meeting_agenda_item.item_id;
  if not found then
    ${q.agendaMissing}
  end if;
  select * into v_row from ${meetings} x where x.${m("id")} = v_item.${g("meeting")} for update;
  if not ${q.runs("v_row")} then
    ${q.forbidden("not allowed to change this agenda")}
  end if;
  delete from ${agenda} y where y.${g("id")} = v_item.${g("id")};
  update ${agenda} y set ${g("ordinal")} = z.n
  from (
    select s.${g("id")} as id, row_number() over (order by s.${g("ordinal")}) as n
    from ${agenda} s where s.${g("meeting")} = v_row.${m("id")}
  ) z
  where y.${g("id")} = z.id and y.${g("ordinal")} <> z.n;
  return ${agendaJson("v_item")};
end;
$$;
${userGrant(`${fn("delete_meeting_agenda_item")}(uuid)`)}
`;
}

function decisionFunctions(ctx: BlockSqlContext, q: MeetingsSql): string {
  const { fn, m, g, d, meetings, agenda, decisions, decisionJson } = q;
  const reactions = managed(ctx, "reactions");
  const hasBody = ctx.has("decisions", "body");

  const record = (type: string, row: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${d("tenant")}, 'id', ${row}.${d("id")}, 'meetingId', ${row}.${d("meeting")}, 'title', ${row}.${d("title")}, 'status', ${row}.${d("status")})`,
      subject: `'meeting-decisions/' || ${row}.${d("id")}::text`,
      tenant: `${row}.${d("tenant")}`,
      audit: {
        category: "data",
        targetType: "meeting_decision",
        recordId: `${row}.${d("id")}::text`,
        targetLabel: `${row}.${d("title")}`,
      },
    });

  const tally =
    reactions === undefined
      ? "null"
      : `${reactions.fn("vote_tally")}(v_decision.${d("tenant")}, ${q.decisionSubject}, v_decision.${d("id")}::text)`;

  return `
-- Records a decision of a meeting. input is { title, body, agendaItemId,
-- status }. It starts proposed, and the attendees vote on it through the
-- reactions block (subject type meeting_decision) until someone decides it.
create or replace function ${fn("record_meeting_decision")}(meeting_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
  v_decision ${decisions};
  v_status text;
  v_agenda uuid;
begin
  ${load(q, "record_meeting_decision", "meeting_id")}
  if not ${q.runs("v_row")} then
    ${q.forbidden("not allowed to record decisions for this meeting")}
  end if;
  if v_row.${m("status")} = 'cancelled' then
    ${q.invalid("a cancelled meeting takes no decisions")}
  end if;
  if jsonb_typeof(record_meeting_decision.input) is distinct from 'object' then
    ${q.invalid("input must be an object")}
  end if;
  if coalesce(length(trim(record_meeting_decision.input ->> 'title')), 0) not between 1 and 300 then
    ${q.invalid("a decision needs a title of 1 to 300 characters")}
  end if;
  v_status := coalesce(record_meeting_decision.input ->> 'status', 'proposed');
  if v_status not in (${quoted(MEETING_DECISION_STATUSES)}) then
    ${q.invalid("status is proposed, passed, rejected or deferred")}
  end if;${
    hasBody
      ? `
  if length(record_meeting_decision.input ->> 'body') > 10000 then
    ${q.invalid("body is at most 10000 characters")}
  end if;`
      : `
  if nullif(trim(record_meeting_decision.input ->> 'body'), '') is not null then
    ${q.invalid("the decisions table has no body column")}
  end if;`
  }
  begin
    v_agenda := nullif(record_meeting_decision.input ->> 'agendaItemId', '')::uuid;
  exception when invalid_text_representation then
    ${q.invalid("agendaItemId is a uuid")}
  end;
  if v_agenda is not null and not exists (
    select 1 from ${agenda} y where y.${g("id")} = v_agenda and y.${g("meeting")} = v_row.${m("id")}
  ) then
    ${q.invalid("the agenda item belongs to another meeting")}
  end if;
  insert into ${decisions} (${d("tenant")}, ${d("meeting")}, ${d("agendaItem")}, ${d("title")}${hasBody ? `, ${d("body")}` : ""}, ${d("status")}, ${d("decidedBy")}, ${d("decidedAt")})
  values (v_row.${m("tenant")}, v_row.${m("id")}, v_agenda, trim(record_meeting_decision.input ->> 'title')${hasBody ? ", nullif(trim(record_meeting_decision.input ->> 'body'), '')" : ""}, v_status,
    case when v_status = 'proposed' then null else auth.uid() end, case when v_status = 'proposed' then null else now() end)
  returning * into v_decision;
  ${record("meeting_decision.recorded", "v_decision")}
  return ${decisionJson("v_decision")};
end;
$$;
${userGrant(`${fn("record_meeting_decision")}(uuid, jsonb)`)}

-- Decides a decision as passed, rejected or deferred. Without status it
-- follows the votes: more up than down passes, more down than up rejects, a
-- tie defers. That needs the reactions block.
create or replace function ${fn("decide_meeting_decision")}(decision_id uuid, status text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
  v_decision ${decisions};
  v_votes jsonb;
  v_status text := decide_meeting_decision.status;
begin
  select * into v_decision from ${decisions} y where y.${d("id")} = decide_meeting_decision.decision_id for update;
  if not found then
    ${q.decisionMissing}
  end if;
  select * into v_row from ${meetings} x where x.${m("id")} = v_decision.${d("meeting")};
  if not ${q.runs("v_row")} then
    ${q.forbidden("not allowed to decide for this meeting")}
  end if;
  if v_status is not null and v_status not in ('passed', 'rejected', 'deferred') then
    ${q.invalid("status is passed, rejected or deferred")}
  end if;
  if v_status is null then
    v_votes := ${tally};
    if v_votes is null then
      ${q.invalid("without the reactions block a decision needs a status")}
    end if;
    v_status := case
      when (v_votes ->> 'up')::integer > (v_votes ->> 'down')::integer then 'passed'
      when (v_votes ->> 'down')::integer > (v_votes ->> 'up')::integer then 'rejected'
      else 'deferred' end;
  end if;
  update ${decisions} y set ${d("status")} = v_status, ${d("decidedBy")} = auth.uid(), ${d("decidedAt")} = now()
  where y.${d("id")} = v_decision.${d("id")}
  returning * into v_decision;
  ${record("meeting_decision.decided", "v_decision")}
  ${ctx.hook("after_meeting_decision", [["uuid", `v_decision.${d("id")}`]])}
  return ${decisionJson("v_decision")};
end;
$$;
${userGrant(`${fn("decide_meeting_decision")}(uuid, text)`)}
`;
}

function actionFunctions(ctx: BlockSqlContext, q: MeetingsSql): string {
  const { fn, m, g, d, x, meetings, agenda, decisions, actions } = q;
  const tasks = ctx.of("tasks");

  return `
-- Opens a task from a meeting. task and assignees are what create_task takes;
-- the task keeps living in the tasks block, and this only records where it
-- came from, with the agenda item and the decision it follows from.
create or replace function ${fn("add_meeting_action_item")}(meeting_id uuid, task jsonb, assignees uuid[] default '{}', agenda_item_id uuid default null, decision_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${meetings};
  v_task jsonb;
begin
  ${load(q, "add_meeting_action_item", "meeting_id")}
  if not ${q.runs("v_row")} then
    ${q.forbidden("not allowed to add action items to this meeting")}
  end if;
  if add_meeting_action_item.agenda_item_id is not null and not exists (
    select 1 from ${agenda} y where y.${g("id")} = add_meeting_action_item.agenda_item_id and y.${g("meeting")} = v_row.${m("id")}
  ) then
    ${q.invalid("the agenda item belongs to another meeting")}
  end if;
  if add_meeting_action_item.decision_id is not null and not exists (
    select 1 from ${decisions} y where y.${d("id")} = add_meeting_action_item.decision_id and y.${d("meeting")} = v_row.${m("id")}
  ) then
    ${q.invalid("the decision belongs to another meeting")}
  end if;
  v_task := ${tasks.fn("create_task")}(v_row.${m("tenant")}, add_meeting_action_item.task, coalesce(add_meeting_action_item.assignees, '{}'));
  insert into ${actions} (${x("task")}, ${x("tenant")}, ${x("meeting")}, ${x("agendaItem")}, ${x("decision")})
  values ((v_task ->> 'id')::uuid, v_row.${m("tenant")}, v_row.${m("id")}, add_meeting_action_item.agenda_item_id, add_meeting_action_item.decision_id);
  ${ctx.record({
    type: "meeting_action_item.created",
    payload: `jsonb_build_object('organizationId', v_row.${m("tenant")}, 'meetingId', v_row.${m("id")}, 'workItemId', (v_task ->> 'id')::uuid, 'title', v_task ->> 'title')`,
    subject: `'meetings/' || v_row.${m("id")}::text`,
    tenant: `v_row.${m("tenant")}`,
    audit: false,
  })}
  return v_task || jsonb_build_object('meetingId', v_row.${m("id")}, 'agendaItemId', add_meeting_action_item.agenda_item_id, 'decisionId', add_meeting_action_item.decision_id);
end;
$$;
${userGrant(`${fn("add_meeting_action_item")}(uuid, jsonb, uuid[], uuid, uuid)`)}
`;
}

export function meetingFunctions(ctx: BlockSqlContext): string {
  const q = meetingsSql(ctx);

  return `${attendeeWriter(ctx, q)}${meetingFunctionsSql(ctx, q)}${attendeeFunctions(ctx, q)}${agendaFunctions(ctx, q)}${decisionFunctions(ctx, q)}${actionFunctions(ctx, q)}`;
}
