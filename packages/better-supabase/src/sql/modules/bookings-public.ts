import type { ModuleContext } from "../context.ts";

import { fail, sha256Hex } from "../shared.ts";

const SERVICE_CALLER = "auth.role() = 'service_role'";
const RATE_SCOPE = "bookings.public";

/** The tables, columns and permission keys the bookings SQL is built from. */
export interface Parts {
  readonly ctx: ModuleContext;
  readonly r: (column: string) => string;
  readonly av: (column: string) => string;
  readonly x: (column: string) => string;
  readonly s: (column: string) => string;
  readonly b: (column: string) => string;
  readonly resources: string;
  readonly availability: string;
  readonly exceptions: string;
  readonly services: string;
  readonly bookings: string;
  readonly manage: string;
  readonly create: string;
  readonly read: string;
}

export const allowed = (tenant: string, key: string): string =>
  `(${SERVICE_CALLER} or coalesce(better_supabase.can('tenant', ${tenant}, ${key}), false))`;

export function record(
  p: Parts,
  type: string,
  id: string,
  tenant: string,
): string {
  return p.ctx.record({
    type,
    payload: `jsonb_build_object('organizationId', ${tenant}, 'id', ${id}, 'resourceId', v_booking.${p.b("resource")}, 'serviceId', v_booking.${p.b("service")})`,
    subject: `'bookings/' || ${id}::text`,
    tenant,
    audit: false,
  });
}

/** A live booking: confirmed, or a hold that has not expired. */
export const live = (p: Parts, alias: string): string =>
  `(${alias}.${p.b("status")} = 'confirmed' or (${alias}.${p.b("status")} = 'hold' and ${alias}.${p.b("holdExpiresAt")} > now()))`;

/** The calendar event that mirrors a confirmed booking, when the resource has a calendar. */
export function calendarMirror(p: Parts, op: "confirm" | "cancel"): string {
  const { ctx } = p;
  if (!ctx.installed("calendar") || !ctx.has("resources", "calendar"))
    return "";
  if (!ctx.has("bookings", "calendarEvent")) return "";
  const c = ctx.of("calendar");
  const events = c.table("events");
  const e = (column: string) => c.col("events", column);
  if (op === "cancel") {
    return `if v_booking.${p.b("calendarEvent")} is not null then
    delete from ${events} where ${e("id")} = v_booking.${p.b("calendarEvent")};
  end if;`;
  }
  const subject =
    c.has("events", "subjectType") && c.has("events", "subjectId")
      ? {
          columns: `, ${e("subjectType")}, ${e("subjectId")}`,
          values: `, 'booking', v_booking.${p.b("id")}::text`,
        }
      : { columns: "", values: "" };
  return `select r.${p.r("calendar")}, r.${p.r("tz")}, sv.${p.s("name")} into v_calendar, v_tz, v_title
  from ${p.resources} r join ${p.services} sv on sv.${p.s("id")} = v_booking.${p.b("service")}
  where r.${p.r("id")} = v_booking.${p.b("resource")};
  if v_calendar is not null then
    insert into ${events} (${e("tenant")}, ${e("calendar")}, ${e("uid")}, ${e("title")}, ${e("startsAt")}, ${e("endsAt")}, ${e("tz")}, ${e("status")}${subject.columns})
    values (v_booking.${p.b("tenant")}, v_calendar, 'booking-' || v_booking.${p.b("id")}::text, coalesce(v_booking.${p.b("customerName")}, v_title), lower(v_booking.${p.b("during")}), upper(v_booking.${p.b("during")}), v_tz, 'confirmed'${subject.values})
    on conflict (${e("calendar")}, ${e("uid")}, ${e("originalStart")}) do update set ${e("startsAt")} = excluded.${e("startsAt")}, ${e("endsAt")} = excluded.${e("endsAt")}
    returning ${e("id")} into v_event;
    update ${p.bookings} set ${p.b("calendarEvent")} = v_event where ${p.b("id")} = v_booking.${p.b("id")};
  end if;`;
}

/** The reminders rule and reminders of a confirmed booking, for its customer. */
export function reminderMirror(p: Parts, op: "confirm" | "cancel"): string {
  const { ctx } = p;
  if (!ctx.installed("reminders")) return "";
  const m = ctx.of("reminders");
  const rules = m.table("rules");
  const reminders = m.table("reminders");
  const u = (column: string) => m.col("rules", column);
  const n = (column: string) => m.col("reminders", column);
  const id = `v_booking.${p.b("id")}::text`;
  const remove = `delete from ${reminders} where ${n("subjectType")} = 'booking' and ${n("subjectId")} = ${id};
  delete from ${rules} where ${u("subjectType")} = 'booking' and ${u("subjectId")} = ${id};`;
  if (op === "cancel") return remove;
  const rrule = m.has("rules", "rrule")
    ? { column: `, ${u("rrule")}`, value: ", 'FREQ=DAILY;COUNT=1'" }
    : { column: "", value: "" };
  const offsets = ctx.has("services", "reminderOffsets")
    ? `insert into ${reminders} (${n("tenant")}, ${n("subjectType")}, ${n("subjectId")}, ${n("user")}, ${n("offsetMinutes")})
  select v_booking.${p.b("tenant")}, 'booking', ${id}, v_booking.${p.b("customerUser")}, o
  from ${p.services} sv, unnest(sv.${p.s("reminderOffsets")}) o
  where sv.${p.s("id")} = v_booking.${p.b("service")};`
    : "";
  return `${remove}
  insert into ${rules} (${u("tenant")}, ${u("subjectType")}, ${u("subjectId")}, ${u("dtstart")}, ${u("tzid")}${rrule.column})
  select v_booking.${p.b("tenant")}, 'booking', ${id}, lower(v_booking.${p.b("during")}), r.${p.r("tz")}${rrule.value}
  from ${p.resources} r where r.${p.r("id")} = v_booking.${p.b("resource")};
  ${offsets}`;
}

/** Throttles a public call by share link and client address, when `rate-limit` is installed. */
function rateLimit(p: Parts, link: string): string {
  if (!p.ctx.installed("rate-limit")) return "";
  return `select l.allowed, l.retry_after into v_allowed, v_retry
  from better_supabase.hit_rate_limit(
    '${RATE_SCOPE}',
    ${link}::text || ':' || coalesce(nullif(trim(split_part(coalesce(nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-forwarded-for', ''), ',', 1)), ''), 'unknown'),
    case when exists (select 1 from better_supabase.rate_limit_rules q where q.scope = '${RATE_SCOPE}') then null else 30 end,
    interval '1 minute'
  ) l;
  if not v_allowed then
    raise exception 'too many booking requests' using errcode = 'BS429', hint = 'BOOKING_RATE_LIMITED', detail = 'retry after ' || v_retry;
  end if;`;
}

export const slotsJson = (
  fn: string,
  service: string,
  start: string,
  end: string,
  tz: string,
  resource: string,
): string =>
  `coalesce((select jsonb_agg(jsonb_build_object('resourceId', t.resource_id, 'startsAt', t.starts_at, 'endsAt', t.ends_at, 'localStart', t.local_start, 'seats', t.seats) order by t.starts_at, t.resource_id) from ${fn}(${service}, ${start}, ${end}, ${tz}, ${resource}) t), '[]'::jsonb)`;

export function publicBooking(p: Parts): string {
  const { ctx, r, s } = p;
  if (!ctx.installed("share-links")) return "";
  const fn = (name: string) => ctx.fn(name);
  const links = ctx.of("share-links");
  const l = (column: string) => `l.${links.col("links", column)}`;
  const anon = (
    signature: string,
  ) => `revoke all on function ${signature} from public;
grant execute on function ${signature} to anon, authenticated, service_role;`;
  const resolve = (
    token: string,
  ) => `if ${token} is null or ${token} !~ '^[0-9a-f]{32,128}$' then
    ${fail("BOOKING_LINK_INVALID", "unknown or expired booking link", "P0002")}
  end if;
  select ${l("id")}, ${l("subjectId")}, ${l("tenant")}::text into v_link, v_subject, v_link_tenant
  from ${links.table("links")} l
  where ${l("tokenHash")} = ${sha256Hex(`convert_to(${token}, 'utf8')`)}
    and ${l("subjectType")} = 'booking_service'
    and ${l("revokedAt")} is null
    and (${l("expiresAt")} is null or ${l("expiresAt")} > now());
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    ${fail("BOOKING_LINK_INVALID", "unknown or expired booking link", "P0002")}
  end if;
  select sv.${s("id")} into v_service from ${p.services} sv
    where sv.${s("id")} = v_subject::uuid and sv.${s("tenant")}::text = v_link_tenant and sv.${s("active")};
  if not found then
    ${fail("BOOKING_LINK_INVALID", "unknown or expired booking link", "P0002")}
  end if;
  ${rateLimit(p, "v_link")}`;
  const declares = `v_link uuid;
  v_subject text;
  v_link_tenant text;
  v_service uuid;
  v_allowed boolean;
  v_retry integer;`;
  return `
-- Public booking through a share link to a service (subjectType
-- "booking_service"): the token is the credential, hashed before the lookup.
create or replace function ${fn("public_booking_service")}(token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  ${declares}
begin
  ${resolve("public_booking_service.token")}
  return (
    select jsonb_build_object('id', sv.${s("id")}, 'name', sv.${s("name")}, 'duration', sv.${s("duration")}::text,
      'resources', coalesce((
        select jsonb_agg(jsonb_build_object('id', rs.${r("id")}, 'name', rs.${r("name")}, 'kind', rs.${r("kind")}, 'tz', rs.${r("tz")}) order by rs.${r("name")})
        from ${p.resources} rs
        where rs.${r("tenant")} = sv.${s("tenant")} and rs.${r("active")}
          and (cardinality(sv.${s("resourceKinds")}) = 0 or rs.${r("kind")} = any (sv.${s("resourceKinds")}))
      ), '[]'::jsonb))
    from ${p.services} sv where sv.${s("id")} = v_service
  );
end;
$$;
${anon(`${fn("public_booking_service")}(text)`)}

create or replace function ${fn("public_available_slots")}(token text, range_start timestamptz, range_end timestamptz, tz text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  ${declares}
begin
  ${resolve("public_available_slots.token")}
  if public_available_slots.tz is not null and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = public_available_slots.tz) then
    ${fail("BOOKING_TZ_INVALID", "tz must be an IANA time zone", "22023")}
  end if;
  if public_available_slots.range_end - public_available_slots.range_start > interval '62 days' then
    ${fail("BOOKING_RANGE_INVALID", "ask for at most 62 days of slots", "22023")}
  end if;
  return ${slotsJson(fn("booking_slots"), "v_service", "public_available_slots.range_start", "public_available_slots.range_end", "public_available_slots.tz", "null")};
end;
$$;
${anon(`${fn("public_available_slots")}(text, timestamptz, timestamptz, text)`)}

-- A guest holds a slot. The result's accessToken confirms or cancels it
-- later; it is returned once and stored hashed.
create or replace function ${fn("public_hold_booking")}(token text, resource uuid, starts_at timestamptz, customer jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  ${declares}
begin
  ${resolve("public_hold_booking.token")}
  if nullif(trim(public_hold_booking.customer ->> 'name'), '') is null
    or coalesce(public_hold_booking.customer ->> 'email', '') !~ '^[^@\\s]+@[^@\\s]+$' then
    ${fail("BOOKING_CUSTOMER_INVALID", "a guest booking needs a name and an email", "22023")}
  end if;
  return ${fn("place_booking")}(v_service, public_hold_booking.resource, public_hold_booking.starts_at, public_hold_booking.customer - 'userId', false, auth.uid());
end;
$$;
${anon(`${fn("public_hold_booking")}(text, uuid, timestamptz, jsonb)`)}

create or replace function ${fn("public_change_booking")}(booking uuid, access_token text, to_status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_allowed boolean;
  v_retry integer;
begin
  if public_change_booking.access_token is null or public_change_booking.access_token !~ '^[0-9a-f]{48}$' then
    ${fail("BOOKING_FORBIDDEN", "not allowed to change this booking")}
  end if;
  ${rateLimit(p, "public_change_booking.booking")}
  return ${fn("change_booking")}(public_change_booking.booking, public_change_booking.to_status, case when public_change_booking.to_status = 'cancelled' then 'customer' end, public_change_booking.access_token);
end;
$$;
${anon(`${fn("public_change_booking")}(uuid, text, text)`)}
`;
}
