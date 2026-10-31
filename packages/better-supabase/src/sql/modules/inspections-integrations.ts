import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { serviceGrant, triggerGrant } from "../shared.ts";
import { inspectionsSql } from "./inspections-sql.ts";

const WHERE = "blocks.inspections.options.calendar";

/** `options.calendar`: the name of the calendar planned inspections mirror to. */
export function calendarName(ctx: BlockSqlContext): string | undefined {
  const value = ctx.option("calendar");

  if (value === undefined || value === null) {
    return undefined;
  }

  if (typeof value !== "string" || value.trim() === "") {
    throw new TypeError(`${WHERE} must be the name of a calendar`);
  }

  return value.trim();
}

/** Another block's context when it is installed with its tables. */
const managed = (
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined =>
  ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;

/**
 * The calendar mirror, the assignment notification and the overdue report. Each
 * one needs its block and renders nothing without it.
 */
export function inspectionIntegrations(ctx: BlockSqlContext): string {
  return `${calendarMirror(ctx)}${assignmentNotice(ctx)}${overdueReport(ctx)}`;
}

/**
 * Keeps one all-day event in the named calendar for each planned or running
 * inspection with a planned start, and removes it when the inspection ends or
 * loses its dates.
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

  const q = inspectionsSql(ctx);
  const { fn, i, inspections } = q;
  const events = calendar.table("events");
  const calendars = calendar.table("calendars");
  const e = (column: string): string => calendar.col("events", column);
  const k = (column: string): string => calendar.col("calendars", column);
  const trigger = ctx.naming.rename("bsb_inspection_calendar");

  const subject =
    calendar.has("events", "subjectType") && calendar.has("events", "subjectId")
      ? {
          columns: `, ${e("subjectType")}, ${e("subjectId")}`,
          values: `, ${q.subject}, new.${i("id")}::text`,
        }
      : { columns: "", values: "" };

  return `
-- Mirrors an inspection with a planned start to an all-day event in the
-- calendar ${name}: one event per inspection, uid inspection-<id>. It skips
-- the organization's missing calendar and removes the event once the
-- inspection closes, is canceled or loses its planned start.
create or replace function ${fn("inspection_calendar_mirror")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_calendar uuid;
begin
  select y.${k("id")} into v_calendar from ${calendars} y
  where y.${k("tenant")} = new.${i("tenant")} and y.${k("name")} = ${sqlString(name)}
  order by y.${k("createdAt")}
  limit 1;
  if v_calendar is null then
    return new;
  end if;
  if new.${i("plannedStart")} is null or new.${i("status")} not in ('planned', 'in_progress') then
    delete from ${events} x where x.${e("calendar")} = v_calendar and x.${e("uid")} = 'inspection-' || new.${i("id")}::text;
    return new;
  end if;
  insert into ${events} (${e("tenant")}, ${e("calendar")}, ${e("uid")}, ${e("title")}, ${e("startsAt")}, ${e("endsAt")}, ${e("allDay")}, ${e("tz")}, ${e("status")}${subject.columns})
  values (new.${i("tenant")}, v_calendar, 'inspection-' || new.${i("id")}::text, new.${i("number")} || ' ' || new.${i("title")},
    (new.${i("plannedStart")}::timestamp at time zone 'UTC'),
    (coalesce(new.${i("plannedEnd")}, new.${i("plannedStart")}) + 1)::timestamp at time zone 'UTC', true, 'UTC', 'confirmed'${subject.values})
  on conflict (${e("calendar")}, ${e("uid")}, ${e("originalStart")}) do update set
    ${e("title")} = excluded.${e("title")}, ${e("startsAt")} = excluded.${e("startsAt")},
    ${e("endsAt")} = excluded.${e("endsAt")}, ${e("updatedAt")} = now();
  return new;
end;
$$;
${triggerGrant(`${fn("inspection_calendar_mirror")}()`)}
drop trigger if exists ${trigger} on ${inspections};
create trigger ${trigger} after insert or update of ${i("plannedStart")}, ${i("plannedEnd")}, ${i("title")}, ${i("status")} on ${inspections}
  for each row execute function ${fn("inspection_calendar_mirror")}();
`;
}

/** Tells a user they joined an inspection's team, once per inspection and user. */
function assignmentNotice(ctx: BlockSqlContext): string {
  if (managed(ctx, "notifications") === undefined) {
    return "";
  }

  const q = inspectionsSql(ctx);
  const { fn, i, m, inspections, members } = q;
  const trigger = ctx.naming.rename("bsb_inspection_assignment");

  return `
-- Notifies a user added to an inspection's team, unless they added themselves.
-- The key keeps a team edit that keeps the user from notifying again.
create or replace function ${fn("inspection_assignment_notice")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${inspections}%rowtype;
  v_claims text;
begin
  if new.${m("user")} is not distinct from auth.uid() then
    return new;
  end if;
  select * into v_row from ${inspections} x where x.${i("id")} = new.${m("inspection")};
  if not found or v_row.${i("status")} not in ('planned', 'in_progress') then
    return new;
  end if;
  ${ctx.notify(
    `jsonb_build_object(
      'type', 'inspection.assigned',
      'tenant', v_row.${i("tenant")},
      'actor', auth.uid(),
      'subject_type', ${q.subject},
      'subject_id', v_row.${i("id")}::text,
      'summary', v_row.${i("number")} || ' ' || v_row.${i("title")},
      'recipients', to_jsonb(array[new.${m("user")}]),
      'key', 'inspection.assigned:' || v_row.${i("id")}::text || ':' || new.${m("user")}::text,
      'data', jsonb_build_object('inspectionId', v_row.${i("id")}, 'role', new.${m("role")})
    )`,
    { indent: "  " },
  )}
  return new;
end;
$$;
${triggerGrant(`${fn("inspection_assignment_notice")}()`)}
drop trigger if exists ${trigger} on ${members};
create trigger ${trigger} after insert on ${members}
  for each row execute function ${fn("inspection_assignment_notice")}();
`;
}

/**
 * Tells the lead (or the team's auditors without one) that an inspection is
 * past its planned end, once per planned end.
 */
function overdueReport(ctx: BlockSqlContext): string {
  const q = inspectionsSql(ctx);
  const { fn, i, m, inspections, members } = q;

  if (managed(ctx, "notifications") === undefined) {
    return `
-- Without the notifications block there is nobody to tell; the function stays so
-- the client and its schedule work the same everywhere.
create or replace function ${fn("notify_overdue_inspections")}()
returns integer
language sql
security definer
set search_path = ''
as $$ select 0 $$;
${serviceGrant(`${fn("notify_overdue_inspections")}()`)}
`;
  }

  const tracked = ctx.has("inspections", "overdueNotifiedFor");

  const once = tracked
    ? `
      and x.${i("overdueNotifiedFor")} is distinct from x.${i("plannedEnd")}`
    : "";

  const mark = tracked
    ? `
    update ${inspections} x set ${i("overdueNotifiedFor")} = v_row.${i("plannedEnd")} where x.${i("id")} = v_row.${i("id")};`
    : "";

  return `
-- Reports each planned or running inspection whose planned end has passed, to
-- its lead or, without one, its auditors, once per planned end (the key keeps
-- a repeat run quiet). Run it daily from a job (the inspections.overdue timer).
create or replace function ${fn("notify_overdue_inspections")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${inspections}%rowtype;
  v_claims text;
  v_to uuid[];
  v_count integer := 0;
begin
  for v_row in
    select * from ${inspections} x
    where x.${i("status")} in ('planned', 'in_progress')
      and x.${i("plannedEnd")} < current_date${once}
    for update skip locked
  loop
    select coalesce(array_agg(y.${m("user")}), '{}'::uuid[]) into v_to from ${members} y
    where y.${m("inspection")} = v_row.${i("id")} and y.${m("role")} = 'lead';
    if cardinality(v_to) = 0 then
      select coalesce(array_agg(y.${m("user")}), '{}'::uuid[]) into v_to from ${members} y
      where y.${m("inspection")} = v_row.${i("id")} and y.${m("role")} = 'auditor';
    end if;
    if cardinality(v_to) > 0 then
      ${ctx.notify(
        `jsonb_build_object(
        'type', 'inspection.overdue',
        'tenant', v_row.${i("tenant")},
        'actor', null,
        'subject_type', ${q.subject},
        'subject_id', v_row.${i("id")}::text,
        'summary', v_row.${i("number")} || ' ' || v_row.${i("title")},
        'recipients', to_jsonb(v_to),
        'key', 'inspection.overdue:' || v_row.${i("id")}::text || ':' || v_row.${i("plannedEnd")}::text,
        'data', jsonb_build_object('inspectionId', v_row.${i("id")}, 'plannedEnd', v_row.${i("plannedEnd")})
      )`,
        { indent: "      " },
      )}
    end if;${mark}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("notify_overdue_inspections")}()`)}
`;
}
