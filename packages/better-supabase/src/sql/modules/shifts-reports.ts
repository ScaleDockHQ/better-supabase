import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER, serviceGrant, userGrant } from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";
import {
  assignmentJson,
  availabilityJson,
  AVAILABILITY_KINDS,
  shiftJson,
  shiftTimeZone,
  sqlList,
  teamType,
} from "./shifts-shared.ts";

/**
 * The time-tracking context shifts_to_time_entries writes to, or undefined when
 * time-tracking isn't installed or its entries table can't take a finished
 * entry with a subject.
 */
export function timeEntriesTarget(
  ctx: BlockSqlContext,
): BlockSqlContext | undefined {
  if (!ctx.installed("time-tracking")) {
    return undefined;
  }

  const time = ctx.of("time-tracking");

  return time.has("entries", "subjectType") &&
    time.has("entries", "subjectId") &&
    time.has("entries", "endedAt")
    ? time
    : undefined;
}

/** The availability, roster, hours and time entry functions. */
export function shiftReportFunctions(ctx: BlockSqlContext): string {
  const shifts = ctx.table("shifts");
  const assignments = ctx.table("assignments");
  const availability = ctx.table("availability");
  const s = (column: string): string => ctx.col("shifts", column);
  const a = (column: string): string => ctx.col("assignments", column);
  const v = (column: string): string => ctx.col("availability", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const team = teamType(ctx);
  const permissions = moduleOperations("shifts");
  const write = ctx.permission("write", permissions.write);
  const request = ctx.permission("request", permissions.request);
  const manage = ctx.permission("manage", permissions.manage);
  const zone = sqlString(shiftTimeZone(ctx));

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const invalid = (message: string): string =>
    fail("SHIFT_INVALID", message, "22023");

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const dayStart = (day: string): string =>
    `(${day})::timestamp at time zone ${zone}`;

  const worked = (row: string): string =>
    `${row}.${s("endsAt")} - make_interval(mins => ${row}.${s("breakMinutes")})`;

  const hours = (interval: string): string =>
    `round((extract(epoch from ${interval}) / 3600)::numeric, 2)`;

  const employees =
    ctx.installed("employees") && ctx.of("employees").hasTable("contracts")
      ? ctx.of("employees")
      : undefined;

  const contractHours =
    employees === undefined
      ? "null::numeric"
      : (() => {
          const e = (column: string): string =>
            employees.col("employees", column);

          const k = (column: string): string =>
            employees.col("contracts", column);

          return `(select k.${k("hoursPerWeek")} from ${employees.table("contracts")} k
        join ${employees.table("employees")} e on e.${e("id")} = k.${k("employee")}
        where e.${e("user")} = p.user_id and k.${k("tenant")} = shift_hours.tenant
          and k.${k("startsOn")} <= shift_hours.week_start and (k.${k("endsOn")} is null or k.${k("endsOn")} >= shift_hours.week_start)
        order by k.${k("startsOn")} desc
        limit 1)::numeric`;
        })();

  const availabilityNote = has("availability", "note");

  return `
-- Sets a member's availability on a day: available, unavailable or
-- preferred, for the whole day or from_time to until_time. kind null clears
-- the day. Planners (shifts.write) set it for others with user_id.
create or replace function ${fn("set_shift_availability")}(tenant ${idType}, on_date date, kind text, from_time time default null, until_time time default null, note text default null, user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${availability}%rowtype;
  v_user uuid := coalesce(set_shift_availability.user_id, (select auth.uid()));
begin
  if v_user is null then
    ${fail("SHIFT_FORBIDDEN", "not allowed to set availability")}
  end if;
  if v_user = (select auth.uid()) then
    if not ${allowed("set_shift_availability.tenant", request)} then
      ${fail("SHIFT_FORBIDDEN", "not allowed to set availability")}
    end if;
  elsif not ${allowed("set_shift_availability.tenant", write)} then
    ${fail("SHIFT_FORBIDDEN", "not allowed to set another member's availability")}
  end if;
  if set_shift_availability.on_date is null then
    ${invalid("on_date is required")}
  end if;
  if set_shift_availability.kind is null then
    delete from ${availability} x
    where x.${v("tenant")} = set_shift_availability.tenant and x.${v("user")} = v_user and x.${v("onDate")} = set_shift_availability.on_date;
    return null;
  end if;
  if set_shift_availability.kind not in ${sqlList(AVAILABILITY_KINDS)} then
    ${invalid(`kind is one of ${AVAILABILITY_KINDS.join(", ")}`)}
  end if;
  if (set_shift_availability.from_time is null) <> (set_shift_availability.until_time is null)
    or set_shift_availability.until_time <= set_shift_availability.from_time then
    ${invalid("from_time and until_time are both set, with until_time after from_time, or both null")}
  end if;
  if set_shift_availability.note is not null and length(set_shift_availability.note) > 500 then
    ${invalid("a note is at most 500 characters")}
  end if;
  insert into ${availability} (${v("tenant")}, ${v("user")}, ${v("onDate")}, ${v("fromTime")}, ${v("untilTime")}, ${v("kind")}${availabilityNote ? `, ${v("note")}` : ""})
  values (set_shift_availability.tenant, v_user, set_shift_availability.on_date, set_shift_availability.from_time, set_shift_availability.until_time, set_shift_availability.kind${availabilityNote ? ", nullif(trim(set_shift_availability.note), '')" : ""})
  on conflict (${v("tenant")}, ${v("user")}, ${v("onDate")}) do update set
    ${v("fromTime")} = excluded.${v("fromTime")},
    ${v("untilTime")} = excluded.${v("untilTime")},
    ${v("kind")} = excluded.${v("kind")}${availabilityNote ? `,\n    ${v("note")} = excluded.${v("note")}` : ""}
  returning * into v_row;
  return ${availabilityJson(ctx, "v_row")};
end;
$$;
${userGrant(`${fn("set_shift_availability")}(${idType}, date, text, time, time, text, uuid)`)}

-- The availability the caller may read from from_date to until_date: their own,
-- or everyone's (or one member's) with shifts.write.
create or replace function ${fn("list_shift_availability")}(tenant ${idType}, from_date date, until_date date, user_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${availabilityJson(ctx, "x")} order by x.${v("onDate")}, x.${v("user")}), '[]'::jsonb)
  from ${availability} x
  where x.${v("tenant")} = list_shift_availability.tenant
    and x.${v("onDate")} between list_shift_availability.from_date and list_shift_availability.until_date
    and (list_shift_availability.user_id is null or x.${v("user")} = list_shift_availability.user_id)
$$;
${userGrant(`${fn("list_shift_availability")}(${idType}, date, date, uuid)`)}

-- The shifts the caller may read that start from from_date to until_date (days in
-- the block's time zone), for one team or all, each with its assigned and
-- requested members. Members see published shifts; planners also drafts.
create or replace function ${fn("roster")}(tenant ${idType}, from_date date, until_date date, team_id ${team} default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${shiftJson(ctx, "x")} || jsonb_build_object('assignments', coalesce((
    select jsonb_agg(${assignmentJson(ctx, "y")} order by y.${a("status")}, y.${a("user")})
    from ${assignments} y
    where y.${a("shift")} = x.${s("id")} and y.${a("status")} <> 'released'
  ), '[]'::jsonb)) order by x.${s("startsAt")}, x.${s("id")}), '[]'::jsonb)
  from ${shifts} x
  where x.${s("tenant")} = roster.tenant
    and x.${s("startsAt")} >= ${dayStart("roster.from_date")}
    and x.${s("startsAt")} < ${dayStart("roster.until_date + 1")}
    and (roster.team_id is null or x.${s("team")} = roster.team_id)
$$;
${userGrant(`${fn("roster")}(${idType}, date, date, ${team})`)}

-- The caller's shifts (assigned or requested) that start from since to until,
-- in every organization, each with its assignment.
create or replace function ${fn("my_shifts")}(since timestamptz default now(), until timestamptz default now() + interval '30 days')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${shiftJson(ctx, "x")} || jsonb_build_object('assignment', ${assignmentJson(ctx, "y")}) order by x.${s("startsAt")}), '[]'::jsonb)
  from ${assignments} y
  join ${shifts} x on x.${s("id")} = y.${a("shift")}
  where y.${a("user")} = (select auth.uid())
    and y.${a("status")} in ('assigned', 'requested')
    and x.${s("status")} <> 'draft'
    and x.${s("startsAt")} >= coalesce(my_shifts.since, now())
    and x.${s("startsAt")} < coalesce(my_shifts.until, now() + interval '30 days')
$$;
${userGrant(`${fn("my_shifts")}(timestamptz, timestamptz)`)}

-- The hours each member is planned for in the week from week_start (shifts
-- not canceled, breaks taken off), next to their contract hours when the
-- employees block keeps contracts.
create or replace function ${fn("shift_hours")}(tenant ${idType}, week_start date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not ${allowed("shift_hours.tenant", manage)} then
    ${fail("SHIFT_FORBIDDEN", "not allowed to read planned hours")}
  end if;
  if shift_hours.week_start is null then
    ${invalid("week_start is required")}
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'shifts', u.shifts,
      'plannedHours', u.planned,
      'contractHours', u.contract,
      'differenceHours', u.planned - u.contract
    ) order by u.planned desc, u.user_id), '[]'::jsonb)
    from (
      select p.user_id, p.shifts, p.planned, ${contractHours} as contract
      from (
        select y.${a("user")} as user_id, count(*)::integer as shifts, ${hours(`sum(${worked("x")} - x.${s("startsAt")})`)} as planned
        from ${assignments} y
        join ${shifts} x on x.${s("id")} = y.${a("shift")}
        where y.${a("tenant")} = shift_hours.tenant
          and y.${a("status")} = 'assigned'
          and x.${s("status")} <> 'canceled'
          and x.${s("startsAt")} >= ${dayStart("shift_hours.week_start")}
          and x.${s("startsAt")} < ${dayStart("shift_hours.week_start + 7")}
        group by y.${a("user")}
      ) p
    ) u
  );
end;
$$;
${userGrant(`${fn("shift_hours")}(${idType}, date)`)}
${timeEntries(ctx)}`;
}

/**
 * Shifts_to_time_entries, when time-tracking can take its entries: a time entry
 * for every assigned shift that ended, linked to its assignment.
 */
function timeEntries(ctx: BlockSqlContext): string {
  const time = timeEntriesTarget(ctx);

  if (time === undefined) {
    return "";
  }

  const shifts = ctx.table("shifts");
  const assignments = ctx.table("assignments");
  const s = (column: string): string => ctx.col("shifts", column);
  const a = (column: string): string => ctx.col("assignments", column);
  const e = (column: string): string => time.col("entries", column);
  const entries = time.table("entries");
  const idType = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);

  const employees = ctx.installed("employees")
    ? ctx.of("employees")
    : undefined;

  const employee =
    time.has("entries", "employee") && employees !== undefined
      ? `(select o.${employees.col("employees", "id")} from ${employees.table("employees")} o where o.${employees.col("employees", "tenant")} = y.${a("tenant")} and o.${employees.col("employees", "user")} = y.${a("user")} limit 1)`
      : undefined;

  return `
-- Writes a time entry for every assigned shift of the tenant that ended
-- before until and has none yet: its start to its end less the break, with
-- subject shift_assignment. Weeks whose timesheet is submitted and entries
-- that overlap one already there are skipped. Returns how many it wrote.
create or replace function ${fn("shifts_to_time_entries")}(tenant ${idType}, until timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_item record;
  v_count integer := 0;
begin
  for v_item in
    select y.${a("id")} as id, y.${a("tenant")} as tenant, y.${a("user")} as user_id, x.${s("startsAt")} as starts_at,
      greatest(x.${s("endsAt")} - make_interval(mins => x.${s("breakMinutes")}), x.${s("startsAt")} + interval '1 minute') as ends_at${employee === undefined ? "" : `,\n      ${employee} as employee_id`}
    from ${assignments} y
    join ${shifts} x on x.${s("id")} = y.${a("shift")}
    where y.${a("tenant")} = shifts_to_time_entries.tenant
      and y.${a("status")} = 'assigned'
      and x.${s("status")} <> 'canceled'
      and x.${s("endsAt")} <= least(coalesce(shifts_to_time_entries.until, now()), now())
      and not exists (
        select 1 from ${entries} t
        where t.${e("tenant")} = y.${a("tenant")} and t.${e("subjectType")} = 'shift_assignment' and t.${e("subjectId")} = y.${a("id")}::text
      )
    order by x.${s("startsAt")}
  loop
    begin
      insert into ${entries} (${e("tenant")}, ${e("user")}${employee === undefined ? "" : `, ${e("employee")}`}, ${e("subjectType")}, ${e("subjectId")}, ${e("startedAt")}, ${e("endedAt")})
      values (v_item.tenant, v_item.user_id${employee === undefined ? "" : ", v_item.employee_id"}, 'shift_assignment', v_item.id::text, v_item.starts_at, v_item.ends_at);
      v_count := v_count + 1;
    exception when exclusion_violation or not_null_violation or sqlstate '55000' then
      null;
    end;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("shifts_to_time_entries")}(${idType}, timestamptz)`)}
`;
}
