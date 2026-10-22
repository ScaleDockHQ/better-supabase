import type { ModuleContractFunction } from "../context.ts";
import type { Parts } from "./bookings-public.ts";

import { sqlIdent } from "../../core/template.ts";
import { fail, lockTable, serviceGrant, userGrant } from "../shared.ts";
import {
  allowed,
  bookingJson,
  calendarMirror,
  record,
  reminderMirror,
} from "./bookings-public.ts";

/** The most occurrences one series books. */
const SERIES_MAX_OCCURRENCES = 366;

/** How far ahead a series may book, in days. */
const SERIES_HORIZON_DAYS = 730;

/**
 * The cancel reason a booking carries for the moment `move_booking` frees its
 * seat, so the cancellation triggers of other modules can ignore it.
 */
export const MOVING_REASON = "bs:moving";

export const SERIES_TABLES = {
  series: {
    name: "booking_series",
    optionalTable: true,
    columns: {
      id: "id",
      tenant: "tenant_id",
      service: "service_id",
      resource: "resource_id",
      rule: "rule",
      startsAt: "starts_at",
      tz: "tz",
      customerName: "customer_name",
      customerEmail: "customer_email",
      customerUser: "customer_user_id",
      status: "status",
      endsAt: "ends_at",
      createdBy: "created_by",
      createdAt: "created_at",
      updatedAt: "updated_at",
    },
  },
} as const;

export function seriesTables(p: Parts): string {
  const { ctx, b, r, s } = p;
  const series = ctx.table("series");
  const e = (column: string): string => ctx.col("series", column);

  const index = (suffix: string): string =>
    sqlIdent(`${ctx.tableName("series").name}_${suffix}`);

  return `
-- A recurring booking: the rule that made it and the occurrences it booked
-- (bookings.series_id). starts_at is the first occurrence; later ones keep its
-- local time in tz, so they move with daylight saving.
create table if not exists ${series} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${ctx.idType} not null,
  ${e("service")} uuid not null references ${p.services} (${s("id")}) on delete restrict,
  ${e("resource")} uuid not null references ${p.resources} (${r("id")}) on delete cascade,
  ${e("rule")} jsonb not null check (jsonb_typeof(${e("rule")}) = 'object'),
  ${e("startsAt")} timestamptz not null,
  ${e("tz")} text not null,
  ${e("customerName")} text,
  ${e("customerEmail")} text,
  ${e("customerUser")} uuid,
  ${e("status")} text not null default 'active' check (${e("status")} in ('active', 'ended', 'cancelled')),
  ${e("endsAt")} timestamptz,
  ${e("createdBy")} uuid,
  ${e("createdAt")} timestamptz not null default now(),
  ${e("updatedAt")} timestamptz not null default now()
);
create index if not exists ${index("tenant_idx")} on ${series} (${e("tenant")}, ${e("startsAt")});
create index if not exists ${index("service_idx")} on ${series} (${e("service")});
create index if not exists ${index("resource_idx")} on ${series} (${e("resource")});
create index if not exists ${index("customer_idx")} on ${series} (${e("customerUser")});
${lockTable(series, { read: true })}
drop policy if exists booking_series_read on ${series};
create policy booking_series_read on ${series} for select to authenticated
using (${ctx.scope.check(e("tenant"), p.read)} or ${e("customerUser")} = (select auth.uid()));
alter table ${p.bookings} add column if not exists ${b("series")} uuid references ${series} (${e("id")}) on delete set null;
create index if not exists bookings_series_idx on ${p.bookings} (${b("series")}, ${b("during")});
`;
}

export function seriesFunctions(p: Parts): string {
  const { ctx, b, r, s } = p;
  const fn = (name: string): string => ctx.fn(name);
  const series = ctx.table("series");
  const e = (column: string): string => ctx.col("series", column);

  const seriesJsonOf = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${e("id")}, 'organizationId', ${alias}.${e("tenant")}::text, 'serviceId', ${alias}.${e("service")}, 'resourceId', ${alias}.${e("resource")}, 'rule', ${alias}.${e("rule")}, 'startsAt', ${alias}.${e("startsAt")}, 'tz', ${alias}.${e("tz")}, 'customerName', ${alias}.${e("customerName")}, 'customerEmail', ${alias}.${e("customerEmail")}, 'customerUserId', ${alias}.${e("customerUser")}, 'status', ${alias}.${e("status")}, 'endsAt', ${alias}.${e("endsAt")}, 'createdAt', ${alias}.${e("createdAt")})`;

  const mayChange = (tenant: string, customer: string): string =>
    `(${allowed(p.scope, tenant, p.manage)} or (${customer} = auth.uid() and ${allowed(p.scope, tenant, p.create)}))`;

  return `
-- The starts of a rule's occurrences from first_start: { freq: daily or
-- weekly, interval, weekdays (1 is Monday, weekly only), count or until }.
-- Each start keeps first_start's local time in tz. At most
-- ${String(SERIES_MAX_OCCURRENCES)} starts, within ${String(SERIES_HORIZON_DAYS)} days.
create or replace function ${fn("booking_series_starts")}(rule jsonb, first_start timestamptz, tz text)
returns setof timestamptz
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_freq text := booking_series_starts.rule ->> 'freq';
  v_interval integer;
  v_days integer[];
  v_count integer;
  v_until timestamptz;
  v_local timestamp;
  v_week0 date;
  v_date date;
  v_at timestamptz;
  v_n integer := 0;
begin
  if jsonb_typeof(booking_series_starts.rule) is distinct from 'object' or v_freq is null or v_freq not in ('daily', 'weekly') then
    ${fail("BOOKING_RULE_INVALID", "rule.freq is daily or weekly", "22023")}
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = booking_series_starts.tz) then
    ${fail("BOOKING_TZ_INVALID", "tz must be an IANA time zone", "22023")}
  end if;
  begin
    v_interval := coalesce((booking_series_starts.rule ->> 'interval')::integer, 1);
    v_count := (booking_series_starts.rule ->> 'count')::integer;
    v_until := (booking_series_starts.rule ->> 'until')::timestamptz;
    v_days := array(select jsonb_array_elements_text(coalesce(booking_series_starts.rule -> 'weekdays', '[]'::jsonb))::integer);
  exception when others then
    ${fail("BOOKING_RULE_INVALID", "rule.interval and rule.count are integers, rule.until a timestamp and rule.weekdays a list of 1 to 7", "22023")}
  end;
  if v_interval not between 1 and 52 then
    ${fail("BOOKING_RULE_INVALID", "rule.interval is between 1 and 52", "22023")}
  end if;
  if v_count is null and v_until is null then
    ${fail("BOOKING_RULE_INVALID", "a rule needs count or until", "22023")}
  end if;
  if v_count is not null and v_count not between 1 and ${String(SERIES_MAX_OCCURRENCES)} then
    ${fail("BOOKING_RULE_INVALID", `rule.count is between 1 and ${String(SERIES_MAX_OCCURRENCES)}`, "22023")}
  end if;
  if v_until is not null and v_until < booking_series_starts.first_start then
    ${fail("BOOKING_RULE_INVALID", "rule.until is before the first occurrence", "22023")}
  end if;
  if exists (select 1 from unnest(v_days) d where d not between 1 and 7) then
    ${fail("BOOKING_RULE_INVALID", "rule.weekdays are 1 (Monday) to 7 (Sunday)", "22023")}
  end if;
  v_local := booking_series_starts.first_start at time zone booking_series_starts.tz;
  if cardinality(v_days) = 0 then
    v_days := array[extract(isodow from v_local)::integer];
  end if;
  v_week0 := v_local::date - (extract(isodow from v_local)::integer - 1);
  for v_offset in 0..${String(SERIES_HORIZON_DAYS)} loop
    v_date := v_local::date + v_offset;
    if (v_freq = 'daily' and v_offset % v_interval = 0)
      or (v_freq = 'weekly' and extract(isodow from v_date)::integer = any (v_days) and ((v_date - v_week0) / 7) % v_interval = 0) then
      v_at := (v_date + v_local::time) at time zone booking_series_starts.tz;
      exit when v_until is not null and v_at > v_until;
      return next v_at;
      v_n := v_n + 1;
      exit when v_n >= coalesce(v_count, ${String(SERIES_MAX_OCCURRENCES)});
    end if;
  end loop;
end;
$$;
${userGrant(`${fn("booking_series_starts")}(jsonb, timestamptz, text)`)}

-- Books every occurrence of a rule from starts_at, each through place_booking,
-- so each one must be an open slot and the exclusion constraint settles races.
-- A taken occurrence fails the whole series (BOOKING_SERIES_CONFLICT), or is
-- skipped and listed with skip_conflicts. The occurrences are confirmed.
create or replace function ${fn("book_series")}(service uuid, resource uuid, starts_at timestamptz, rule jsonb, customer jsonb, skip_conflicts boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_customer jsonb := coalesce(book_series.customer, '{}'::jsonb);
  v_user uuid := auth.uid();
  v_tenant ${ctx.idType};
  v_tz text;
  v_series ${series}%rowtype;
  v_at timestamptz;
  v_booking jsonb;
  v_booked jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
begin
  select ${s("tenant")} into v_tenant from ${p.services} where ${s("id")} = book_series.service and ${s("active")};
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
  select ${r("tz")} into v_tz from ${p.resources} where ${r("id")} = book_series.resource and ${r("tenant")} = v_tenant and ${r("active")};
  if not found then
    ${fail("BOOKING_RESOURCE_NOT_FOUND", "resource not found", "P0002")}
  end if;
  v_tz := coalesce(nullif(book_series.rule ->> 'tz', ''), v_tz);
  insert into ${series} (${e("tenant")}, ${e("service")}, ${e("resource")}, ${e("rule")}, ${e("startsAt")}, ${e("tz")}, ${e("customerName")}, ${e("customerEmail")}, ${e("customerUser")}, ${e("createdBy")})
  values (v_tenant, book_series.service, book_series.resource, book_series.rule - 'tz', book_series.starts_at, v_tz, v_customer ->> 'name', lower(v_customer ->> 'email'), v_user, auth.uid())
  returning * into v_series;
  for v_at in select t from ${fn("booking_series_starts")}(book_series.rule, book_series.starts_at, v_tz) t loop
    begin
      v_booking := ${fn("place_booking")}(book_series.service, book_series.resource, v_at, v_customer, true, v_user);
      update ${p.bookings} set ${b("series")} = v_series.${e("id")} where ${b("id")} = (v_booking ->> 'id')::uuid;
      v_booked := v_booked || jsonb_build_array((v_booking - 'accessToken') || jsonb_build_object('seriesId', v_series.${e("id")}));
    exception when sqlstate '23P01' then
      if not coalesce(book_series.skip_conflicts, false) then
        ${fail("BOOKING_SERIES_CONFLICT", "an occurrence is not an open slot", "23P01")}
      end if;
      v_skipped := v_skipped || jsonb_build_array(v_at);
    end;
  end loop;
  if jsonb_array_length(v_booked) = 0 then
    ${fail("BOOKING_SERIES_CONFLICT", "no occurrence is an open slot", "23P01")}
  end if;
  update ${series} set ${e("endsAt")} = ((v_booked -> -1) ->> 'endsAt')::timestamptz where ${e("id")} = v_series.${e("id")}
  returning * into v_series;
  return jsonb_build_object('series', ${seriesJsonOf("v_series")}, 'bookings', v_booked, 'skipped', v_skipped);
end;
$$;
${userGrant(`${fn("book_series")}(uuid, uuid, timestamptz, jsonb, jsonb, boolean)`)}

-- Moves a live booking to starts_at, keeping its id. The booking frees its
-- seat for the check (cancel reason ${MOVING_REASON}), so the new time must be
-- an open slot apart from the booking itself; a taken time puts it back.
create or replace function ${fn("move_booking")}(booking uuid, starts_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_old ${p.bookings}%rowtype;
  v_booking ${p.bookings}%rowtype;
  v_capacity integer;
  v_length interval;
  v_before interval;
  v_after interval;
  v_moved boolean := false;
  v_calendar uuid;
  v_tz text;
  v_title text;
  v_event uuid;
begin
  select * into v_old from ${p.bookings} bk where bk.${b("id")} = move_booking.booking for update;
  if not found then
    ${fail("BOOKING_NOT_FOUND", "booking not found", "P0002")}
  end if;
  if v_old.${b("status")} = 'cancelled' then
    ${fail("BOOKING_STATUS_INVALID", "a cancelled booking can't move", "22023")}
  end if;
  v_booking := v_old;
  if lower(v_old.${b("during")}) = move_booking.starts_at then
    return ${bookingJson(p, "v_booking")};
  end if;
  v_length := upper(v_old.${b("during")}) - lower(v_old.${b("during")});
  v_before := lower(v_old.${b("during")}) - lower(v_old.${b("blocked")});
  v_after := upper(v_old.${b("blocked")}) - upper(v_old.${b("during")});
  update ${p.bookings} bk set ${b("status")} = 'cancelled', ${b("holdExpiresAt")} = null, ${b("cancelledAt")} = now(), ${b("cancelReason")} = '${MOVING_REASON}'
  where bk.${b("id")} = v_old.${b("id")};
  if not exists (
    select 1 from ${fn("booking_slots")}(v_old.${b("service")}, move_booking.starts_at, move_booking.starts_at + v_length, null, v_old.${b("resource")}) t
    where t.starts_at = move_booking.starts_at
  ) then
    ${fail("BOOKING_SLOT_UNAVAILABLE", "that time is not an open slot", "23P01")}
  end if;
  select rs.${r("capacity")} into v_capacity from ${p.resources} rs where rs.${r("id")} = v_old.${b("resource")};
  for v_seat in 1..v_capacity loop
    begin
      update ${p.bookings} bk set ${b("status")} = v_old.${b("status")}, ${b("holdExpiresAt")} = v_old.${b("holdExpiresAt")}, ${b("cancelledAt")} = null, ${b("cancelReason")} = null,
        ${b("seat")} = v_seat,
        ${b("during")} = tstzrange(move_booking.starts_at, move_booking.starts_at + v_length),
        ${b("blocked")} = tstzrange(move_booking.starts_at - v_before, move_booking.starts_at + v_length + v_after),
        ${b("updatedAt")} = now()
      where bk.${b("id")} = v_old.${b("id")}
      returning * into v_booking;
      v_moved := true;
      exit;
    exception when exclusion_violation then
      null;
    end;
  end loop;
  if not v_moved then
    ${fail("BOOKING_SLOT_UNAVAILABLE", "that time was just taken", "23P01")}
  end if;
  if v_booking.${b("status")} = 'confirmed' then
    ${calendarMirror(p, "cancel").replaceAll("v_booking.", "v_old.")}
    ${reminderMirror(p, "cancel")}
    ${calendarMirror(p, "confirm")}
    ${reminderMirror(p, "confirm")}
  end if;
  ${record(p, "booking.rescheduled", `v_booking.${b("id")}`, `v_booking.${b("tenant")}`)}
  return ${bookingJson(p, "v_booking")};
end;
$$;
${serviceGrant(`${fn("move_booking")}(uuid, timestamptz)`)}

-- Moves one occurrence, or this one and every later live one in its series
-- by the same amount (scope 'following'), in one transaction.
create or replace function ${fn("reschedule_booking")}(booking uuid, starts_at timestamptz, scope text default 'one')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking ${p.bookings}%rowtype;
  v_shift interval;
  v_id uuid;
  v_moved jsonb := '[]'::jsonb;
begin
  select * into v_booking from ${p.bookings} bk where bk.${b("id")} = reschedule_booking.booking;
  if not found or not ${mayChange(`v_booking.${b("tenant")}`, `v_booking.${b("customerUser")}`)} then
    ${fail("BOOKING_NOT_FOUND", "booking not found", "P0002")}
  end if;
  if reschedule_booking.scope is null or reschedule_booking.scope not in ('one', 'following') then
    ${fail("BOOKING_SCOPE_INVALID", "scope is one or following", "22023")}
  end if;
  if reschedule_booking.scope = 'one' or v_booking.${b("series")} is null then
    return jsonb_build_array(${fn("move_booking")}(v_booking.${b("id")}, reschedule_booking.starts_at));
  end if;
  v_shift := reschedule_booking.starts_at - lower(v_booking.${b("during")});
  -- Later occurrences move first when the shift is positive, so a series never
  -- collides with itself.
  for v_id in
    select bk.${b("id")} from ${p.bookings} bk
    where bk.${b("series")} = v_booking.${b("series")} and bk.${b("status")} <> 'cancelled'
      and lower(bk.${b("during")}) >= lower(v_booking.${b("during")})
    order by case when v_shift > interval '0' then lower(bk.${b("during")}) end desc, lower(bk.${b("during")})
  loop
    v_moved := v_moved || jsonb_build_array(${fn("move_booking")}(v_id, (select lower(x.${b("during")}) from ${p.bookings} x where x.${b("id")} = v_id) + v_shift));
  end loop;
  return (select jsonb_agg(m order by (m ->> 'startsAt')::timestamptz) from jsonb_array_elements(v_moved) m);
end;
$$;
${userGrant(`${fn("reschedule_booking")}(uuid, timestamptz, text)`)}

-- Cancels one occurrence, or this one and every later live one in its series
-- (scope 'following'); the series then ends before it, or is cancelled when
-- nothing is left. Returns how many bookings it cancelled.
create or replace function ${fn("cancel_booking_series")}(booking uuid, scope text default 'following', reason text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_booking ${p.bookings}%rowtype;
  v_id uuid;
  v_count integer := 0;
begin
  select * into v_booking from ${p.bookings} bk where bk.${b("id")} = cancel_booking_series.booking;
  if not found or not ${mayChange(`v_booking.${b("tenant")}`, `v_booking.${b("customerUser")}`)} then
    ${fail("BOOKING_NOT_FOUND", "booking not found", "P0002")}
  end if;
  if cancel_booking_series.scope is null or cancel_booking_series.scope not in ('one', 'following') then
    ${fail("BOOKING_SCOPE_INVALID", "scope is one or following", "22023")}
  end if;
  for v_id in
    select bk.${b("id")} from ${p.bookings} bk
    where bk.${b("status")} <> 'cancelled'
      and (bk.${b("id")} = v_booking.${b("id")}
        or (cancel_booking_series.scope = 'following' and bk.${b("series")} = v_booking.${b("series")}
          and lower(bk.${b("during")}) >= lower(v_booking.${b("during")})))
    order by lower(bk.${b("during")})
  loop
    perform ${fn("change_booking")}(v_id, 'cancelled', cancel_booking_series.reason, null);
    v_count := v_count + 1;
  end loop;
  if cancel_booking_series.scope = 'following' and v_booking.${b("series")} is not null then
    update ${series} sr set
      ${e("status")} = case when exists (
        select 1 from ${p.bookings} bk where bk.${b("series")} = sr.${e("id")} and bk.${b("status")} <> 'cancelled'
      ) then 'ended' else 'cancelled' end,
      ${e("endsAt")} = (select max(upper(bk.${b("during")})) from ${p.bookings} bk where bk.${b("series")} = sr.${e("id")} and bk.${b("status")} <> 'cancelled'),
      ${e("updatedAt")} = now()
    where sr.${e("id")} = v_booking.${b("series")};
  end if;
  return v_count;
end;
$$;
${userGrant(`${fn("cancel_booking_series")}(uuid, text, text)`)}

-- A series with its occurrences, as the caller: the policies show it to the
-- tenant's readers and to its customer.
create or replace function ${fn("get_booking_series")}(series_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${seriesJsonOf("sr")} || jsonb_build_object('bookings', coalesce((
    select jsonb_agg(${bookingJson(p, "bk")} order by lower(bk.${b("during")}))
    from ${p.bookings} bk where bk.${b("series")} = sr.${e("id")}
  ), '[]'::jsonb))
  from ${series} sr
  where sr.${e("id")} = get_booking_series.series_id
$$;
${userGrant(`${fn("get_booking_series")}(uuid)`)}
`;
}

export function seriesContract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "book_series",
      args: ["uuid", "uuid", "timestamptz", "jsonb", "jsonb", "boolean"],
      returns: "jsonb",
    },
    {
      name: "reschedule_booking",
      args: ["uuid", "timestamptz", "text"],
      returns: "jsonb",
    },
    {
      name: "cancel_booking_series",
      args: ["uuid", "text", "text"],
      returns: "integer",
    },
    { name: "get_booking_series", args: ["uuid"], returns: "jsonb" },
  ];
}
