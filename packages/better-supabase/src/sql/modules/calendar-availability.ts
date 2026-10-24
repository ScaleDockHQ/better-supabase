import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlTableSpec,
} from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  fail,
  lockTable,
  serviceGrant,
  triggerGrant,
  userGrant,
} from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The weekly hours a member works, in their own time zone. */
export const WORKING_HOURS_TABLE: BlockSqlTableSpec = {
  name: "calendar_working_hours",
  app: {},
  lifecycle: { tenant: "tenant", user: "user", export: true },
  optionalTable: true,
  columns: {
    id: "id",
    tenant: "tenant_id",
    user: "user_id",
    weekday: "weekday",
    startsAt: "starts_at",
    endsAt: "ends_at",
    tz: "tz",
  },
};

export const EVENT_KINDS = "('event', 'out_of_office', 'focus_time')";
export const TRANSPARENCIES = "('opaque', 'transparent')";

/** The longest window one free/busy query covers. */
const MAX_DAYS = 62;

/** The most members one free/busy query covers. */
const MAX_USERS = 100;

/**
 * `calendar_rule_starts`: the occurrence starts of an RRULE in [range_start,
 * range_end), the same ones the reminders block's `expandRule` returns in
 * TypeScript (DAILY, WEEKLY, MONTHLY and YEARLY with INTERVAL, COUNT, UNTIL,
 * BYDAY with ordinals, BYMONTHDAY, BYMONTH, BYSETPOS and WKST, in the rule's
 * time zone). A rule it can't read counts as one occurrence at dtstart.
 */
function ruleStarts(ctx: BlockSqlContext): string {
  const fn = ctx.fn("calendar_rule_starts");

  return `
create or replace function ${fn}(dtstart timestamptz, tz text, rrule text, range_start timestamptz, range_end timestamptz)
returns setof timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_parts jsonb;
  v_freq text;
  v_interval integer := 1;
  v_count integer;
  v_until timestamptz;
  v_alldays integer[] := '{}';
  v_ordinals integer[] := '{}';
  v_ordinal_days integer[] := '{}';
  v_bymonthday integer[] := '{}';
  v_bymonth integer[] := '{}';
  v_bysetpos integer[] := '{}';
  v_wkst integer := 1;
  v_local timestamp;
  v_anchor date;
  v_time time;
  v_week date;
  v_moved date;
  v_target date;
  v_periods integer;
  v_first integer := 0;
  v_generated integer := 0;
  v_found integer := 0;
  v_index integer;
  v_dates date[];
  v_sorted date[];
  v_date date;
  v_when timestamptz;
  v_year integer;
  v_month integer;
  v_len integer;
  v_day integer;
  v_item text;
  v_match text[];
  v_i integer;
  v_names constant text[] := array['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
begin
  if calendar_rule_starts.dtstart is null or calendar_rule_starts.range_start is null or calendar_rule_starts.range_end is null then
    return;
  end if;
  v_local := calendar_rule_starts.dtstart at time zone coalesce(calendar_rule_starts.tz, 'UTC');
  v_anchor := v_local::date;
  v_time := v_local::time;
  select coalesce(jsonb_object_agg(upper(btrim(split_part(p, '=', 1))), btrim(split_part(p, '=', 2))), '{}'::jsonb)
    into v_parts
  from unnest(string_to_array(regexp_replace(btrim(coalesce(calendar_rule_starts.rrule, '')), '^RRULE:', '', 'i'), ';')) p
  where p like '%=%';
  v_freq := upper(v_parts ->> 'FREQ');
  if v_freq is null or v_freq not in ('DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY') then
    if calendar_rule_starts.dtstart >= calendar_rule_starts.range_start and calendar_rule_starts.dtstart < calendar_rule_starts.range_end then
      return next calendar_rule_starts.dtstart;
    end if;
    return;
  end if;
  if v_parts ->> 'INTERVAL' ~ '^[0-9]{1,6}$' then
    v_interval := greatest((v_parts ->> 'INTERVAL')::integer, 1);
  end if;
  if v_parts ->> 'COUNT' ~ '^[0-9]{1,6}$' then
    v_count := (v_parts ->> 'COUNT')::integer;
  end if;
  if v_parts ->> 'UNTIL' ~ '^[0-9]{8}T[0-9]{6}Z$' then
    v_until := (regexp_replace(v_parts ->> 'UNTIL', '^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$', '\\1-\\2-\\3 \\4:\\5:\\6+00'))::timestamptz;
  elsif v_parts ->> 'UNTIL' ~ '^[0-9]{8}$' then
    v_until := ((to_date(v_parts ->> 'UNTIL', 'YYYYMMDD') + 1)::timestamp at time zone coalesce(calendar_rule_starts.tz, 'UTC')) - interval '1 microsecond';
  end if;
  if upper(v_parts ->> 'WKST') = any (v_names) then
    v_wkst := array_position(v_names, upper(v_parts ->> 'WKST'));
  end if;
  foreach v_item in array string_to_array(coalesce(upper(v_parts ->> 'BYDAY'), ''), ',') loop
    v_match := regexp_match(btrim(v_item), '^([+-]?[0-9]{1,2})?(MO|TU|WE|TH|FR|SA|SU)$');
    continue when v_match is null;
    v_alldays := v_alldays || array_position(v_names, v_match[2]);
    if v_match[1] is not null and v_match[1]::integer <> 0 then
      v_ordinals := v_ordinals || v_match[1]::integer;
      v_ordinal_days := v_ordinal_days || array_position(v_names, v_match[2]);
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTHDAY', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,2}$' and btrim(v_item)::integer <> 0 then
      v_bymonthday := v_bymonthday || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYMONTH', ''), ',') loop
    if btrim(v_item) ~ '^[0-9]{1,2}$' and btrim(v_item)::integer between 1 and 12 then
      v_bymonth := v_bymonth || btrim(v_item)::integer;
    end if;
  end loop;
  foreach v_item in array string_to_array(coalesce(v_parts ->> 'BYSETPOS', ''), ',') loop
    if btrim(v_item) ~ '^[+-]?[0-9]{1,3}$' and btrim(v_item)::integer <> 0 then
      v_bysetpos := v_bysetpos || btrim(v_item)::integer;
    end if;
  end loop;
  -- Without COUNT, start a period before the window instead of at dtstart.
  if v_count is null then
    v_target := (calendar_rule_starts.range_start at time zone coalesce(calendar_rule_starts.tz, 'UTC'))::date;
    if v_target > v_anchor then
      v_periods := case v_freq
        when 'DAILY' then v_target - v_anchor
        when 'WEEKLY' then floor((v_target - (v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7)))::numeric / 7)::integer
        when 'MONTHLY' then (extract(year from v_target)::integer - extract(year from v_anchor)::integer) * 12 + extract(month from v_target)::integer - extract(month from v_anchor)::integer
        else extract(year from v_target)::integer - extract(year from v_anchor)::integer
      end;
      v_first := greatest(0, floor(v_periods::numeric / v_interval)::integer - 1);
    end if;
  end if;
  for v_index in v_first .. v_first + 3999 loop
    v_dates := '{}';
    if v_freq = 'DAILY' then
      v_date := v_anchor + v_index * v_interval;
      if cardinality(v_alldays) = 0 or extract(isodow from v_date)::integer = any (v_alldays) then
        v_dates := array[v_date];
      end if;
    elsif v_freq = 'WEEKLY' then
      v_week := v_anchor - ((extract(isodow from v_anchor)::integer - v_wkst + 7) % 7) + v_index * v_interval * 7;
      select coalesce(array_agg(v_week + ((d - v_wkst + 7) % 7)), '{}') into v_dates
      from unnest(case when cardinality(v_alldays) = 0 then array[extract(isodow from v_anchor)::integer] else v_alldays end) d;
    else
      if v_freq = 'MONTHLY' then
        v_moved := (v_anchor + make_interval(months => v_index * v_interval))::date;
      else
        v_moved := (v_anchor + make_interval(years => v_index * v_interval))::date;
      end if;
      v_year := extract(year from v_moved)::integer;
      foreach v_month in array case when cardinality(v_bymonth) = 0 then array[extract(month from v_moved)::integer] else v_bymonth end loop
        v_len := extract(day from (make_date(v_year, v_month, 1) + interval '1 month' - interval '1 day'))::integer;
        if cardinality(v_ordinals) > 0 then
          for v_i in 1 .. cardinality(v_ordinals) loop
            if v_ordinals[v_i] > 0 then
              v_day := 1 + ((v_ordinal_days[v_i] - extract(isodow from make_date(v_year, v_month, 1))::integer + 7) % 7) + (v_ordinals[v_i] - 1) * 7;
            else
              v_day := v_len - ((extract(isodow from make_date(v_year, v_month, v_len))::integer - v_ordinal_days[v_i] + 7) % 7) + (v_ordinals[v_i] + 1) * 7;
            end if;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif cardinality(v_alldays) > 0 then
          v_dates := v_dates || array(
            select make_date(v_year, v_month, d) from generate_series(1, v_len) d
            where extract(isodow from make_date(v_year, v_month, d))::integer = any (v_alldays)
          );
        elsif cardinality(v_bymonthday) > 0 then
          foreach v_day in array v_bymonthday loop
            v_day := case when v_day > 0 then v_day else v_len + v_day + 1 end;
            if v_day between 1 and v_len then
              v_dates := v_dates || make_date(v_year, v_month, v_day);
            end if;
          end loop;
        elsif extract(day from v_moved)::integer <= v_len then
          v_dates := v_dates || make_date(v_year, v_month, extract(day from v_moved)::integer);
        end if;
      end loop;
    end if;
    if cardinality(v_bysetpos) > 0 and cardinality(v_dates) > 0 then
      select array_agg(d order by d) into v_sorted from (select distinct d from unnest(v_dates) d) s;
      select coalesce(array_agg(distinct v_sorted[case when p > 0 then p else cardinality(v_sorted) + p + 1 end]), '{}') into v_dates
      from unnest(v_bysetpos) p
      where (case when p > 0 then p else cardinality(v_sorted) + p + 1 end) between 1 and cardinality(v_sorted);
    end if;
    foreach v_date in array coalesce((select array_agg(d order by d) from unnest(v_dates) d), '{}') loop
      v_when := (v_date + v_time) at time zone coalesce(calendar_rule_starts.tz, 'UTC');
      -- A wall time that happens twice (DST ends) takes the earlier instant,
      -- as Temporal's compatible disambiguation does; Postgres takes the later.
      if ((v_when - interval '1 hour') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '1 hour';
      elsif ((v_when - interval '30 minutes') at time zone coalesce(calendar_rule_starts.tz, 'UTC')) = v_date + v_time then
        v_when := v_when - interval '30 minutes';
      end if;
      continue when v_when < calendar_rule_starts.dtstart;
      if v_until is not null and v_when > v_until then
        return;
      end if;
      v_generated := v_generated + 1;
      if v_count is not null and v_generated > v_count then
        return;
      end if;
      if v_when >= calendar_rule_starts.range_end then
        return;
      end if;
      continue when v_when < calendar_rule_starts.range_start;
      return next v_when;
      v_found := v_found + 1;
      if v_found >= 1000 then
        return;
      end if;
    end loop;
  end loop;
end;
$$;
${userGrant(`${fn}(timestamptz, text, text, timestamptz, timestamptz)`)}
`;
}

/** The leave rows of approved, not cancelled requests as out-of-office blocks. */
function leaveBlocks(ctx: BlockSqlContext, hoursTz: string): string {
  if (!ctx.installed("leave")) {
    return "";
  }

  const leave = ctx.of("leave");

  if (leave.mode === "custom") {
    return "";
  }

  const r = (column: string) => `r.${leave.col("requests", column)}`;

  return `
  union all
  select ${r("user")}, 'out_of_office'::text, t.s, t.en, null::uuid, true
  from ${leave.table("requests")} r
  cross join lateral (select ${hoursTz} as tz) z
  cross join lateral (
    select
      (case when ${r("partial")} = 'afternoon' then ${r("startsOn")} + time '12:00' else ${r("startsOn")}::timestamp end) at time zone z.tz as s,
      (case ${r("partial")} when 'morning' then ${r("startsOn")} + time '12:00' when 'afternoon' then (${r("startsOn")} + 1)::timestamp else (${r("endsOn")} + 1)::timestamp end) at time zone z.tz as en
  ) t
  where ${r("tenant")} = calendar_busy_blocks.tenant
    and ${r("user")} = any (calendar_busy_blocks.user_ids)
    and ${r("approvedAt")} is not null
    and ${r("cancelledAt")} is null
    and ${r("partial")} <> 'hours'
    and t.s < calendar_busy_blocks.range_end
    and t.en > calendar_busy_blocks.range_start`;
}

/**
 * `calendar_busy_blocks`: when each member is busy, from the events on the
 * calendars they own, the events they are invited to and haven't declined, and
 * approved leave. Series expand with `calendar_rule_starts`, without their
 * EXDATEs and overridden occurrences. Cancelled and transparent events don't
 * count. Only other functions call it.
 */
function busyBlocks(ctx: BlockSqlContext): string {
  const fn = ctx.fn("calendar_busy_blocks");
  const calendars = ctx.table("calendars");
  const events = ctx.table("events");
  const k = (column: string) => `k.${ctx.col("calendars", column)}`;
  const e = (column: string) => `e.${ctx.col("events", column)}`;
  const kind = ctx.has("events", "kind") ? e("kind") : "'event'::text";

  const opaque = ctx.has("events", "transparency")
    ? `${e("transparency")} <> 'transparent'`
    : "true";

  const declines = ctx.has("events", "autoDecline")
    ? `(${kind} <> 'event' and ${e("autoDecline")})`
    : "false";

  const sources: string[] = [];

  if (ctx.has("calendars", "ownerType") && ctx.has("calendars", "ownerId")) {
    sources.push(`select m.u as user_id, e.${ctx.col("events", "id")} as event_id
    from unnest(calendar_busy_blocks.user_ids) m (u)
    join ${calendars} k on ${k("tenant")} = calendar_busy_blocks.tenant and ${k("ownerType")} = 'user' and ${k("ownerId")} = m.u::text
    join ${events} e on ${e("calendar")} = ${k("id")}`);
  }

  if (ctx.hasTable("attendees")) {
    const a = (column: string) => `a.${ctx.col("attendees", column)}`;
    const d = (column: string) => `d.${ctx.col("attendees", column)}`;

    sources.push(`select ${a("user")} as user_id, e.${ctx.col("events", "id")} as event_id
    from ${ctx.table("attendees")} a
    join ${events} e on (${e("id")} = ${a("event")} or ${e("recurrence")} = ${a("event")})
    where ${a("tenant")} = calendar_busy_blocks.tenant
      and ${a("user")} = any (calendar_busy_blocks.user_ids)
      and ${a("response")} <> 'declined'
      and not exists (
        select 1 from ${ctx.table("attendees")} d
        where ${d("event")} = ${e("id")} and ${d("user")} = ${a("user")} and ${d("response")} = 'declined'
      )`);
  }

  const hoursTz = ctx.hasTable("workingHours")
    ? `coalesce((select h.${ctx.col("workingHours", "tz")} from ${ctx.table("workingHours")} h where h.${ctx.col("workingHours", "tenant")} = calendar_busy_blocks.tenant and h.${ctx.col("workingHours", "user")} = r.${ctx.installed("leave") ? ctx.of("leave").col("requests", "user") : "user_id"} limit 1), 'UTC')`
    : "'UTC'";

  const eventBlocks =
    sources.length === 0
      ? `select null::uuid, null::text, null::timestamptz, null::timestamptz, null::uuid, null::boolean where false`
      : `select c.user_id, c.kind, c.starts_at, c.ends_at, c.event_id, c.declines
  from candidates c
  where c.rrule is null and c.starts_at < calendar_busy_blocks.range_end and c.ends_at > calendar_busy_blocks.range_start
  union all
  select c.user_id, c.kind, s.at, s.at + (c.ends_at - c.starts_at), c.event_id, c.declines
  from candidates c
  cross join lateral ${ctx.fn("calendar_rule_starts")}(c.starts_at, c.tz, c.rrule, calendar_busy_blocks.range_start - (c.ends_at - c.starts_at), calendar_busy_blocks.range_end) s (at)
  where c.rrule is not null and c.recurrence is null
    and c.starts_at < calendar_busy_blocks.range_end
    and s.at + (c.ends_at - c.starts_at) > calendar_busy_blocks.range_start
    and not (s.at = any (c.exdates))
    and not exists (
      select 1 from ${events} o
      where o.${ctx.col("events", "recurrence")} = c.event_id and o.${ctx.col("events", "originalStart")} = s.at
    )`;

  const candidates =
    sources.length === 0
      ? ""
      : `with sources as (
    ${sources.join("\n    union\n    ")}
  ),
  candidates as (
    select distinct s.user_id, ${e("id")} as event_id, ${kind} as kind, ${e("startsAt")} as starts_at, ${e("endsAt")} as ends_at,
      ${e("tz")} as tz, ${e("rrule")} as rrule, ${e("recurrence")} as recurrence, ${e("exdates")} as exdates, ${declines} as declines
    from sources s
    join ${events} e on ${e("id")} = s.event_id
    where ${e("tenant")} = calendar_busy_blocks.tenant
      and ${e("status")} <> 'cancelled'
      and ${opaque}
      and ${e("startsAt")} < calendar_busy_blocks.range_end
  )
  `;

  return `
create or replace function ${fn}(tenant ${ctx.idType}, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns table (user_id uuid, kind text, starts_at timestamptz, ends_at timestamptz, event_id uuid, declines boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return query
  ${candidates}${eventBlocks}${leaveBlocks(ctx, hoursTz)};
end;
$$;
${serviceGrant(`${fn}(${ctx.idType}, uuid[], timestamptz, timestamptz)`)}
`;
}

/** A jsonb array of `{ startsAt, endsAt }` for a tstzmultirange. */
const rangesJson = (multirange: string): string =>
  `coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest(${multirange}) x), '[]'::jsonb)`;

function workingHoursFunctions(ctx: BlockSqlContext): string {
  if (!ctx.hasTable("workingHours")) {
    return "";
  }

  const hours = ctx.table("workingHours");
  const h = (column: string) => ctx.col("workingHours", column);
  const perms = moduleOperations("calendar");
  const manage = ctx.permission("manage", perms.manage);
  const read = ctx.permission("read", perms.read);

  const allowed = (tenant: string, key: string) =>
    `(auth.role() = 'service_role' or ${ctx.scope.can(tenant, key)})`;

  return `
-- Replaces a member's weekly hours: hours is [{ weekday, start, end }] with
-- ISO weekdays (1 is Monday) and local times in tz. Members set their own;
-- calendar managers set anyone's. An empty list clears them.
create or replace function ${ctx.fn("set_calendar_working_hours")}(tenant ${ctx.idType}, user_id uuid, tz text, hours jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := coalesce(set_calendar_working_hours.user_id, auth.uid());
  v_count integer;
begin
  if v_user is null then
    ${fail("CALENDAR_FORBIDDEN", "sign in or pass a user id")}
  end if;
  if not (
    ${allowed("set_calendar_working_hours.tenant", manage)}
    or (v_user = auth.uid() and ${ctx.scope.can("set_calendar_working_hours.tenant", read)})
  ) then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to set these working hours")}
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(set_calendar_working_hours.tz, 'UTC')) then
    ${fail("CALENDAR_TZ_INVALID", "tz must be an IANA time zone", "22023")}
  end if;
  if jsonb_typeof(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) <> 'array' or exists (
    select 1 from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x
    where case
      when jsonb_typeof(x) <> 'object'
        or coalesce(x ->> 'weekday', '') !~ '^[1-7]$'
        or coalesce(x ->> 'start', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        or coalesce(x ->> 'end', '') !~ '^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$' then true
      else x ->> 'end' <> '24:00' and (x ->> 'end')::time <= (x ->> 'start')::time
    end
  ) then
    ${fail("CALENDAR_HOURS_INVALID", "hours must be [{ weekday 1-7, start HH:MM, end HH:MM }] with end after start", "22023")}
  end if;
  delete from ${hours} where ${h("tenant")} = set_calendar_working_hours.tenant and ${h("user")} = v_user;
  insert into ${hours} (${h("tenant")}, ${h("user")}, ${h("weekday")}, ${h("startsAt")}, ${h("endsAt")}, ${h("tz")})
  select distinct set_calendar_working_hours.tenant, v_user, (x ->> 'weekday')::smallint, (x ->> 'start')::time, (x ->> 'end')::time, coalesce(set_calendar_working_hours.tz, 'UTC')
  from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${userGrant(`${ctx.fn("set_calendar_working_hours")}(${ctx.idType}, uuid, text, jsonb)`)}

-- [{ userId, tz, hours: [{ weekday, start, end }] }] for the members that set
-- working hours. Runs as the caller, so the table's policy decides.
create or replace function ${ctx.fn("list_calendar_working_hours")}(tenant ${ctx.idType}, user_ids uuid[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('userId', w.user_id, 'tz', w.tz, 'hours', w.hours) order by w.user_id), '[]'::jsonb)
  from (
    select h.${h("user")} as user_id, min(h.${h("tz")}) as tz,
      jsonb_agg(jsonb_build_object('weekday', h.${h("weekday")}, 'start', to_char(h.${h("startsAt")}, 'HH24:MI'), 'end', case when h.${h("endsAt")} = time '24:00' then '24:00' else to_char(h.${h("endsAt")}, 'HH24:MI') end) order by h.${h("weekday")}, h.${h("startsAt")}) as hours
    from ${hours} h
    where h.${h("tenant")} = list_calendar_working_hours.tenant
      and (list_calendar_working_hours.user_ids is null or h.${h("user")} = any (list_calendar_working_hours.user_ids))
    group by h.${h("user")}
  ) w
$$;
${userGrant(`${ctx.fn("list_calendar_working_hours")}(${ctx.idType}, uuid[])`)}
`;
}

function freeBusy(ctx: BlockSqlContext): string {
  const fn = ctx.fn("calendar_free_busy");
  const perms = moduleOperations("calendar");
  const read = ctx.permission("read", perms.read);
  const h = (column: string) => `h.${ctx.col("workingHours", column)}`;

  const hours = ctx.hasTable("workingHours")
    ? `,
  hours as (
    select ${h("user")} as user_id, ${h("tz")} as tz,
      tstzrange((d.day + ${h("startsAt")}) at time zone ${h("tz")}, (d.day + ${h("endsAt")}) at time zone ${h("tz")}) * v_window as during
    from ${ctx.table("workingHours")} h
    cross join lateral generate_series(
      ((calendar_free_busy.range_start at time zone ${h("tz")})::date - 1)::timestamp,
      ((calendar_free_busy.range_end at time zone ${h("tz")})::date)::timestamp,
      interval '1 day'
    ) d (day)
    where ${h("tenant")} = calendar_free_busy.tenant
      and ${h("user")} = any (calendar_free_busy.user_ids)
      and extract(isodow from d.day) = ${h("weekday")}
  )`
    : "";

  const working = ctx.hasTable("workingHours")
    ? `,
      'tz', (select min(w.tz) from hours w where w.user_id = u.user_id),
      'workingHours', case when exists (select 1 from hours w where w.user_id = u.user_id)
        then ${rangesJson("(select range_agg(w.during) from hours w where w.user_id = u.user_id)")} end`
    : "";

  const of = (filter: string) =>
    rangesJson(
      `(select range_agg(b.during) from blocks b where b.user_id = u.user_id${filter})`,
    );

  return `
-- Busy, out-of-office and focus-time ranges per member, merged and clipped to
-- [range_start, range_end), with their working hours in it. It answers when
-- people are busy, never why: it returns no titles.
create or replace function ${fn}(tenant ${ctx.idType}, user_ids uuid[], range_start timestamptz, range_end timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_window tstzrange;
begin
  if calendar_free_busy.range_start is null or calendar_free_busy.range_end is null
    or calendar_free_busy.range_end <= calendar_free_busy.range_start
    or calendar_free_busy.range_end - calendar_free_busy.range_start > interval '${MAX_DAYS} days' then
    ${fail("CALENDAR_RANGE_INVALID", `the range must end after it starts and cover at most ${MAX_DAYS} days`, "22023")}
  end if;
  if coalesce(cardinality(calendar_free_busy.user_ids), 0) not between 1 and ${MAX_USERS} then
    ${fail("CALENDAR_RANGE_INVALID", `ask for 1 to ${MAX_USERS} members`, "22023")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can("calendar_free_busy.tenant", read)}) then
    ${fail("CALENDAR_FORBIDDEN", "not allowed to read this calendar")}
  end if;
  v_window := tstzrange(calendar_free_busy.range_start, calendar_free_busy.range_end);
  return (
    with blocks as (
      select b.user_id, b.kind, tstzrange(b.starts_at, b.ends_at) * v_window as during
      from ${ctx.fn("calendar_busy_blocks")}(calendar_free_busy.tenant, calendar_free_busy.user_ids, calendar_free_busy.range_start, calendar_free_busy.range_end) b
    )${hours},
    members as (
      select m.user_id, min(m.ord) as ord
      from unnest(calendar_free_busy.user_ids) with ordinality m (user_id, ord)
      where m.user_id is not null
      group by m.user_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'busy', ${of("")},
      'outOfOffice', ${of(" and b.kind = 'out_of_office'")},
      'focusTime', ${of(" and b.kind = 'focus_time'")}${working}
    ) order by u.ord), '[]'::jsonb)
    from members u
  );
end;
$$;
${userGrant(`${fn}(${ctx.idType}, uuid[], timestamptz, timestamptz)`)}
`;
}

/**
 * Auto-decline: an invitation to a single event (or one occurrence override)
 * starts declined when the invitee has approved leave, or an out-of-office or
 * focus-time block with auto_decline, over it. Saving such a block declines the
 * open invitations it covers. Series are left alone, and an answer the invitee
 * already gave is never changed.
 */
function autoDecline(ctx: BlockSqlContext): string {
  if (!ctx.hasTable("attendees") || !ctx.has("events", "kind")) {
    return "";
  }

  const events = ctx.table("events");
  const attendees = ctx.table("attendees");
  const e = (column: string) => ctx.col("events", column);
  const a = (column: string) => ctx.col("attendees", column);
  const busy = ctx.fn("calendar_busy_blocks");
  const invite = ctx.fn("calendar_attendee_auto_decline");
  const block = ctx.fn("calendar_block_auto_decline");

  const inviteTrigger = sqlIdent(
    `${ctx.tableName("attendees").name}_auto_decline`,
  );

  const owned =
    ctx.has("calendars", "ownerType") &&
    ctx.has("calendars", "ownerId") &&
    ctx.has("events", "autoDecline");

  const blockSql = owned
    ? `
create or replace function ${block}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
begin
  select case when k.${ctx.col("calendars", "ownerId")} ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then k.${ctx.col("calendars", "ownerId")}::uuid end
    into v_owner
  from ${ctx.table("calendars")} k
  where k.${ctx.col("calendars", "id")} = new.${e("calendar")} and k.${ctx.col("calendars", "ownerType")} = 'user';
  if v_owner is null then
    return null;
  end if;
  update ${attendees} a set ${a("response")} = 'declined'
  from ${events} x
  where a.${a("event")} = x.${e("id")}
    and a.${a("user")} = v_owner
    and a.${a("response")} = 'needs-action'
    and x.${e("tenant")} = new.${e("tenant")}
    and x.${e("id")} <> new.${e("id")}
    and x.${e("rrule")} is null
    and x.${e("kind")} = 'event'
    and x.${e("status")} <> 'cancelled'
    and x.${e("startsAt")} < new.${e("endsAt")}
    and x.${e("endsAt")} > new.${e("startsAt")};
  return null;
end;
$$;
${triggerGrant(`${block}()`)}
drop trigger if exists ${sqlIdent(`${ctx.tableName("events").name}_auto_decline`)} on ${events};
create trigger ${sqlIdent(`${ctx.tableName("events").name}_auto_decline`)}
after insert or update of ${e("startsAt")}, ${e("endsAt")}, ${e("kind")}, ${e("autoDecline")}, ${e("status")} on ${events}
for each row
when (new.${e("kind")} <> 'event' and new.${e("autoDecline")} and new.${e("status")} <> 'cancelled' and new.${e("rrule")} is null)
execute function ${block}();
`
    : "";

  return `
create or replace function ${invite}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event record;
begin
  select x.${e("tenant")} as tenant, x.${e("startsAt")} as starts_at, x.${e("endsAt")} as ends_at
    into v_event
  from ${events} x
  where x.${e("id")} = new.${a("event")} and x.${e("rrule")} is null and x.${e("kind")} = 'event' and x.${e("status")} <> 'cancelled';
  if found and exists (
    select 1 from ${busy}(v_event.tenant, array[new.${a("user")}], v_event.starts_at, v_event.ends_at) b
    where b.declines and b.event_id is distinct from new.${a("event")}
  ) then
    new.${a("response")} := 'declined';
  end if;
  return new;
end;
$$;
${triggerGrant(`${invite}()`)}
drop trigger if exists ${inviteTrigger} on ${attendees};
create trigger ${inviteTrigger}
before insert or update of ${a("user")} on ${attendees}
for each row
when (new.${a("user")} is not null and new.${a("response")} = 'needs-action')
execute function ${invite}();
${blockSql}`;
}

/** The working-hours table, created with the calendar's tables. */
export function workingHoursTable(ctx: BlockSqlContext): string {
  if (!ctx.manages || !ctx.hasTable("workingHours")) {
    return "";
  }

  const hours = ctx.table("workingHours");
  const h = (column: string) => ctx.col("workingHours", column);
  const name = ctx.tableName("workingHours").name;
  const read = ctx.permission("read", moduleOperations("calendar").read);

  return `create table if not exists ${hours} (
  ${h("id")} uuid primary key default gen_random_uuid(),
  ${h("tenant")} ${ctx.idType} not null,
  ${h("user")} uuid not null,
  ${h("weekday")} smallint not null check (${h("weekday")} between 1 and 7),
  ${h("startsAt")} time not null,
  ${h("endsAt")} time not null,
  ${h("tz")} text not null default 'UTC',
  check (${h("endsAt")} > ${h("startsAt")}),
  unique (${h("tenant")}, ${h("user")}, ${h("weekday")}, ${h("startsAt")})
);
${lockTable(hours, { read: true })}
drop policy if exists ${name}_read on ${hours};
create policy ${name}_read on ${hours} for select to authenticated
using (${ctx.scope.check(h("tenant"), read)} or ${h("user")} = (select auth.uid()));
`;
}

/** Availability: working hours, free/busy and auto-decline. */
export function availabilitySql(ctx: BlockSqlContext): string {
  return `${ruleStarts(ctx)}${busyBlocks(ctx)}${workingHoursFunctions(ctx)}${freeBusy(ctx)}${autoDecline(ctx)}`;
}

export function availabilityContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "calendar_rule_starts",
      args: ["timestamptz", "text", "text", "timestamptz", "timestamptz"],
      returns: "setof timestamptz",
    },
    {
      name: "calendar_free_busy",
      args: ["{id}", "uuid[]", "timestamptz", "timestamptz"],
      returns: "jsonb",
    },
    ...(ctx.hasTable("workingHours")
      ? [
          {
            name: "set_calendar_working_hours",
            args: ["{id}", "uuid", "text", "jsonb"],
            returns: "integer",
          },
          {
            name: "list_calendar_working_hours",
            args: ["{id}", "uuid[]"],
            returns: "jsonb",
          },
        ]
      : []),
  ];
}
