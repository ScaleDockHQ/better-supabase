import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { triggerGrant } from "../shared.ts";
import { managed, meetingsSql } from "./meetings-sql.ts";

const WHERE = "blocks.meetings.options.calendar";

/** `options.calendar`: the name of the calendar meetings mirror to. */
function calendarName(ctx: BlockSqlContext): string | undefined {
  const value = ctx.option("calendar");

  if (value === undefined || value === null) {
    return undefined;
  }

  if (typeof value !== "string" || value.trim() === "") {
    throw new TypeError(`${WHERE} must be the name of a calendar`);
  }

  return value.trim();
}

/**
 * The calendar mirror and the invitation notice. Each one needs its block and
 * renders nothing without it.
 */
export function meetingIntegrations(ctx: BlockSqlContext): string {
  return `${calendarMirror(ctx)}${invitationNotice(ctx)}`;
}

/**
 * Keeps one event in the named calendar for each planned or running meeting,
 * with the attendees invited, and removes it when the meeting ends.
 */
function calendarMirror(ctx: BlockSqlContext): string {
  const name = calendarName(ctx);
  const calendar = managed(ctx, "calendar");

  if (name === undefined) {
    return "";
  }

  if (calendar === undefined) {
    throw new TypeError(
      `${WHERE} needs the calendar block's tables; calendar can't be in custom mode`,
    );
  }

  const q = meetingsSql(ctx);
  const { fn, m, a, meetings, attendees } = q;
  const events = calendar.table("events");
  const calendars = calendar.table("calendars");
  const e = (column: string): string => calendar.col("events", column);
  const k = (column: string): string => calendar.col("calendars", column);
  const trigger = ctx.naming.rename("bsb_meeting_calendar");
  const attendeeTrigger = ctx.naming.rename("bsb_meeting_calendar_attendee");

  const subject =
    calendar.has("events", "subjectType") && calendar.has("events", "subjectId")
      ? {
          columns: `, ${e("subjectType")}, ${e("subjectId")}`,
          values: `, ${q.subject}, new.${m("id")}::text`,
        }
      : { columns: "", values: "" };

  const invites =
    calendar.hasTable("attendees") &&
    calendar.has("attendees", "email") &&
    calendar.has("attendees", "user") &&
    calendar.has("attendees", "role");

  const c = (column: string): string => calendar.col("attendees", column);

  const invite = invites
    ? `
-- Invites an attendee to the meeting's calendar event by their account email.
-- An attendee without an email is skipped. A chair becomes the event's chair.
create or replace function ${fn("meeting_calendar_attendee")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event uuid;
  v_email text;
begin
  if tg_op = 'DELETE' then
    delete from ${calendar.table("attendees")} y
    using ${events} x
    where x.${e("uid")} = 'meeting-' || old.${a("meeting")}::text
      and x.${e("tenant")} = old.${a("tenant")} and y.${c("event")} = x.${e("id")} and y.${c("user")} = old.${a("user")};
    return old;
  end if;
  select x.${e("id")} into v_event from ${events} x
  where x.${e("tenant")} = new.${a("tenant")} and x.${e("uid")} = 'meeting-' || new.${a("meeting")}::text
  limit 1;
  select u.email into v_email from auth.users u where u.id = new.${a("user")};
  if v_event is null or v_email is null then
    return new;
  end if;
  insert into ${calendar.table("attendees")} (${c("tenant")}, ${c("event")}, ${c("email")}, ${c("user")}, ${c("role")})
  values (new.${a("tenant")}, v_event, v_email, new.${a("user")}, case new.${a("role")} when 'chair' then 'chair' when 'guest' then 'optional' else 'required' end)
  on conflict (${c("event")}, ${c("email")}) do update set ${c("role")} = excluded.${c("role")};
  return new;
end;
$$;
${triggerGrant(`${fn("meeting_calendar_attendee")}()`)}
drop trigger if exists ${attendeeTrigger} on ${attendees};
create trigger ${attendeeTrigger} after insert or update of ${a("role")} or delete on ${attendees}
  for each row execute function ${fn("meeting_calendar_attendee")}();
`
    : "";

  return `
-- Mirrors a planned or running meeting to an event in the calendar ${name}:
-- one event per meeting, uid meeting-<id>. It skips the organization's missing
-- calendar and removes the event once the meeting is held or cancelled.
create or replace function ${fn("meeting_calendar_mirror")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_calendar uuid;
begin
  select y.${k("id")} into v_calendar from ${calendars} y
  where y.${k("tenant")} = new.${m("tenant")} and y.${k("name")} = ${sqlString(name)}
  order by y.${k("createdAt")}
  limit 1;
  if v_calendar is null then
    return new;
  end if;
  if new.${m("status")} not in ('planned', 'in_progress') then
    delete from ${events} x where x.${e("calendar")} = v_calendar and x.${e("uid")} = 'meeting-' || new.${m("id")}::text;
    return new;
  end if;
  insert into ${events} (${e("tenant")}, ${e("calendar")}, ${e("uid")}, ${e("title")}, ${e("startsAt")}, ${e("endsAt")}, ${e("allDay")}, ${e("tz")}, ${e("status")}${subject.columns})
  values (new.${m("tenant")}, v_calendar, 'meeting-' || new.${m("id")}::text, new.${m("title")},
    new.${m("startsAt")}, coalesce(new.${m("endsAt")}, new.${m("startsAt")} + interval '1 hour'), false, 'UTC', 'confirmed'${subject.values})
  on conflict (${e("calendar")}, ${e("uid")}, ${e("originalStart")}) do update set
    ${e("title")} = excluded.${e("title")}, ${e("startsAt")} = excluded.${e("startsAt")},
    ${e("endsAt")} = excluded.${e("endsAt")}, ${e("updatedAt")} = now();
  return new;
end;
$$;
${triggerGrant(`${fn("meeting_calendar_mirror")}()`)}
drop trigger if exists ${trigger} on ${meetings};
create trigger ${trigger} after insert or update of ${m("startsAt")}, ${m("endsAt")}, ${m("title")}, ${m("status")} on ${meetings}
  for each row execute function ${fn("meeting_calendar_mirror")}();
${invite}`;
}

/** Tells a user they were invited to a meeting, once per meeting and user. */
function invitationNotice(ctx: BlockSqlContext): string {
  if (managed(ctx, "notifications") === undefined) {
    return "";
  }

  const q = meetingsSql(ctx);
  const { fn, m, a, meetings, attendees } = q;
  const trigger = ctx.naming.rename("bsb_meeting_invitation");

  return `
-- Notifies a user invited to a planned or running meeting, unless they invited
-- themselves. The key keeps a later edit from notifying again.
create or replace function ${fn("meeting_invitation_notice")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${meetings}%rowtype;
  v_claims text;
begin
  if new.${a("user")} is not distinct from auth.uid() then
    return new;
  end if;
  select * into v_row from ${meetings} x where x.${m("id")} = new.${a("meeting")};
  if not found or v_row.${m("status")} not in ('planned', 'in_progress') then
    return new;
  end if;
  ${ctx.notify(
    `jsonb_build_object(
      'type', 'meeting.invited',
      'tenant', v_row.${m("tenant")},
      'actor', auth.uid(),
      'subject_type', ${q.subject},
      'subject_id', v_row.${m("id")}::text,
      'summary', v_row.${m("title")},
      'recipients', to_jsonb(array[new.${a("user")}]),
      'key', 'meeting.invited:' || v_row.${m("id")}::text || ':' || new.${a("user")}::text,
      'data', jsonb_build_object('meetingId', v_row.${m("id")}, 'role', new.${a("role")}, 'startsAt', v_row.${m("startsAt")})
    )`,
    { indent: "  " },
  )}
  return new;
end;
$$;
${triggerGrant(`${fn("meeting_invitation_notice")}()`)}
drop trigger if exists ${trigger} on ${attendees};
create trigger ${trigger} after insert on ${attendees}
  for each row execute function ${fn("meeting_invitation_notice")}();
`;
}
