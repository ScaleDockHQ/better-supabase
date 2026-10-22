SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."calendar_working_hours" (
  "id"        uuid                   NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id" uuid                   NOT NULL,
  "user_id"   uuid                   NOT NULL,
  "weekday"   smallint               NOT NULL,
  "starts_at" time without time zone NOT NULL,
  "ends_at"   time without time zone NOT NULL,
  "tz"        text                   NOT NULL DEFAULT 'UTC'::text,
  CONSTRAINT "calendar_working_hours_check" CHECK ((ends_at > starts_at)),
  CONSTRAINT "calendar_working_hours_pkey" PRIMARY KEY (id),
  CONSTRAINT "calendar_working_hours_tenant_id_user_id_weekday_starts_at_key" UNIQUE (tenant_id, user_id, weekday, starts_at),
  CONSTRAINT "calendar_working_hours_weekday_check" CHECK (((weekday >= 1) AND (weekday <= 7)))
);

ALTER TABLE "better_supabase"."calendar_working_hours"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."booking_resources"
  ADD COLUMN "host_user_id" uuid;

ALTER TABLE "better_supabase"."booking_resources"
  ADD COLUMN "check_busy" boolean NOT NULL DEFAULT false;

ALTER TABLE "better_supabase"."calendar_events"
  ADD COLUMN "kind" text NOT NULL DEFAULT 'event'::text;

ALTER TABLE "better_supabase"."calendar_events"
  ADD COLUMN "transparency" text NOT NULL DEFAULT 'opaque'::text;

ALTER TABLE "better_supabase"."calendar_events"
  ADD COLUMN "auto_decline" boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION api.calendar_busy_blocks (
  tenant      uuid,
  user_ids    uuid[],
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS TABLE (
    user_id   uuid,
    kind      text,
    starts_at timestamp with time zone,
    ends_at   timestamp with time zone,
    event_id  uuid,
    declines  boolean
  )
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."calendar_busy_blocks"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.calendar_free_busy (
  tenant      uuid,
  user_ids    uuid[],
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."calendar_free_busy"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.calendar_rule_starts (
  dtstart     timestamp with time zone,
  tz          text,
  rrule       text,
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS SETOF timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."calendar_rule_starts"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_calendar_working_hours (
  tenant   uuid,
  user_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_calendar_working_hours"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_calendar_working_hours (
  tenant  uuid,
  user_id uuid,
  tz      text,
  hours   jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_calendar_working_hours"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.booking_slots (
  service       uuid,
  range_start   timestamp with time zone,
  range_end     timestamp with time zone,
  tz            text,
  only_resource uuid
)
  RETURNS TABLE (
    resource_id uuid,
    starts_at   timestamp with time zone,
    ends_at     timestamp with time zone,
    local_start timestamp without time zone,
    seats       integer
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_service record;
  v_resource record;
  v_open tstzmultirange;
  v_window tstzrange;
  v_floor timestamptz;
  v_step interval;
  v_at timestamptz;
  v_block tstzrange;
  v_free integer;
  v_busy tstzmultirange := '{}'::tstzmultirange;
begin
  select sv."tenant_id" as tenant, sv."duration" as duration, sv."buffer_before" as before, sv."buffer_after" as after,
      sv."resource_kinds" as kinds, sv."step" as step, sv."min_notice" as notice
    into v_service
    from "better_supabase"."booking_services" sv where sv."id" = booking_slots.service and sv."active";
  if not found or booking_slots.range_end is null or booking_slots.range_start is null then
    return;
  end if;
  v_step := coalesce(v_service.step, v_service.duration);
  v_floor := greatest(booking_slots.range_start, now() + v_service.notice);
  for v_resource in
    select rs."id" as id, rs."tz" as tz, rs."capacity" as capacity, case when rs."check_busy" then rs."host_user_id" end as host
    from "better_supabase"."booking_resources" rs
    where rs."tenant_id" = v_service.tenant and rs."active"
      and (cardinality(v_service.kinds) = 0 or rs."kind" = any (v_service.kinds))
      and (booking_slots.only_resource is null or rs."id" = booking_slots.only_resource)
    order by rs."name", rs."id"
  loop
    select coalesce(range_agg(tstzrange((d.day + a."starts_at") at time zone v_resource.tz, (d.day + a."ends_at") at time zone v_resource.tz)), '{}'::tstzmultirange)
      into v_open
      from (
        select g::date as day
        from generate_series((v_floor at time zone v_resource.tz)::date - 1, (booking_slots.range_end at time zone v_resource.tz)::date, interval '1 day') g
      ) d
      join "better_supabase"."booking_availability" a on a."resource_id" = v_resource.id and a."weekday" = extract(isodow from d.day)::integer;
    v_open := v_open + coalesce((select range_agg(e."during") from "better_supabase"."booking_exceptions" e where e."resource_id" = v_resource.id and e."available"), '{}'::tstzmultirange);
    v_open := v_open - coalesce((select range_agg(e."during") from "better_supabase"."booking_exceptions" e where e."resource_id" = v_resource.id and not e."available"), '{}'::tstzmultirange);
    v_busy := '{}'::tstzmultirange;
    if v_resource.host is not null then
      select coalesce(range_agg(tstzrange(bb.starts_at, bb.ends_at)), '{}'::tstzmultirange) into v_busy
      from "better_supabase"."calendar_busy_blocks"(v_service.tenant, array[v_resource.host], v_floor - v_service.before, booking_slots.range_end + v_service.after) bb
      where bb.starts_at < bb.ends_at and not exists (select 1 from "better_supabase"."bookings" bk where bk."calendar_event_id" = bb.event_id and bk."resource_id" = v_resource.id);
    end if;
    for v_window in select w from unnest(v_open) w loop
      v_at := lower(v_window);
      if v_at < v_floor then
        v_at := v_at + ceil(extract(epoch from (v_floor - v_at)) / extract(epoch from v_step)) * v_step;
      end if;
      while v_at + v_service.duration <= upper(v_window) and v_at + v_service.duration <= booking_slots.range_end loop
        v_block := tstzrange(v_at - v_service.before, v_at + v_service.duration + v_service.after);
        select count(*)::integer into v_free
        from generate_series(1, v_resource.capacity) seat
        where not exists (
          select 1 from "better_supabase"."bookings" bk
          where bk."resource_id" = v_resource.id and bk."seat" = seat.seat
            and (bk."status" = 'confirmed' or (bk."status" = 'hold' and bk."hold_expires_at" > now())) and bk."blocked" && v_block
        );
        if v_free > 0 and not (v_busy && v_block) then
          resource_id := v_resource.id;
          starts_at := v_at;
          ends_at := v_at + v_service.duration;
          local_start := v_at at time zone coalesce(booking_slots.tz, v_resource.tz);
          seats := v_free;
          return next;
        end if;
        v_at := v_at + v_step;
      end loop;
    end loop;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.calendar_attendee_auto_decline()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_event record;
begin
  select x."tenant_id" as tenant, x."starts_at" as starts_at, x."ends_at" as ends_at
    into v_event
  from "better_supabase"."calendar_events" x
  where x."id" = new."event_id" and x."rrule" is null and x."kind" = 'event' and x."status" <> 'cancelled';
  if found and exists (
    select 1 from "better_supabase"."calendar_busy_blocks"(v_event.tenant, array[new."user_id"], v_event.starts_at, v_event.ends_at) b
    where b.declines and b.event_id is distinct from new."event_id"
  ) then
    new."response" := 'declined';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.calendar_block_auto_decline()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_owner uuid;
begin
  select case when k."owner_id" ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then k."owner_id"::uuid end
    into v_owner
  from "better_supabase"."calendars" k
  where k."id" = new."calendar_id" and k."owner_type" = 'user';
  if v_owner is null then
    return null;
  end if;
  update "better_supabase"."calendar_attendees" a set "response" = 'declined'
  from "better_supabase"."calendar_events" x
  where a."event_id" = x."id"
    and a."user_id" = v_owner
    and a."response" = 'needs-action'
    and x."tenant_id" = new."tenant_id"
    and x."id" <> new."id"
    and x."rrule" is null
    and x."kind" = 'event'
    and x."status" <> 'cancelled'
    and x."starts_at" < new."ends_at"
    and x."ends_at" > new."starts_at";
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.calendar_busy_blocks (
  tenant      uuid,
  user_ids    uuid[],
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS TABLE (
    user_id   uuid,
    kind      text,
    starts_at timestamp with time zone,
    ends_at   timestamp with time zone,
    event_id  uuid,
    declines  boolean
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  return query
  with sources as (
    select m.u as user_id, e."id" as event_id
    from unnest(calendar_busy_blocks.user_ids) m (u)
    join "better_supabase"."calendars" k on k."tenant_id" = calendar_busy_blocks.tenant and k."owner_type" = 'user' and k."owner_id" = m.u::text
    join "better_supabase"."calendar_events" e on e."calendar_id" = k."id"
    union
    select a."user_id" as user_id, e."id" as event_id
    from "better_supabase"."calendar_attendees" a
    join "better_supabase"."calendar_events" e on (e."id" = a."event_id" or e."recurrence_id" = a."event_id")
    where a."tenant_id" = calendar_busy_blocks.tenant
      and a."user_id" = any (calendar_busy_blocks.user_ids)
      and a."response" <> 'declined'
      and not exists (
        select 1 from "better_supabase"."calendar_attendees" d
        where d."event_id" = e."id" and d."user_id" = a."user_id" and d."response" = 'declined'
      )
  ),
  candidates as (
    select distinct s.user_id, e."id" as event_id, e."kind" as kind, e."starts_at" as starts_at, e."ends_at" as ends_at,
      e."tz" as tz, e."rrule" as rrule, e."recurrence_id" as recurrence, e."exdates" as exdates, (e."kind" <> 'event' and e."auto_decline") as declines
    from sources s
    join "better_supabase"."calendar_events" e on e."id" = s.event_id
    where e."tenant_id" = calendar_busy_blocks.tenant
      and e."status" <> 'cancelled'
      and e."transparency" <> 'transparent'
      and e."starts_at" < calendar_busy_blocks.range_end
  )
  select c.user_id, c.kind, c.starts_at, c.ends_at, c.event_id, c.declines
  from candidates c
  where c.rrule is null and c.starts_at < calendar_busy_blocks.range_end and c.ends_at > calendar_busy_blocks.range_start
  union all
  select c.user_id, c.kind, s.at, s.at + (c.ends_at - c.starts_at), c.event_id, c.declines
  from candidates c
  cross join lateral "better_supabase"."calendar_rule_starts"(c.starts_at, c.tz, c.rrule, calendar_busy_blocks.range_start - (c.ends_at - c.starts_at), calendar_busy_blocks.range_end) s (at)
  where c.rrule is not null and c.recurrence is null
    and c.starts_at < calendar_busy_blocks.range_end
    and s.at + (c.ends_at - c.starts_at) > calendar_busy_blocks.range_start
    and not (s.at = any (c.exdates))
    and not exists (
      select 1 from "better_supabase"."calendar_events" o
      where o."recurrence_id" = c.event_id and o."original_start" = s.at
    );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.calendar_feed (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_subject text;
  v_tenant text;
  v_calendar uuid;
begin
  if calendar_feed.token is null or length(calendar_feed.token) < 32 then
    return null;
  end if;
  select l."subject_id", l."tenant_id"::text into v_subject, v_tenant
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(calendar_feed.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'calendar'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses");
  if v_subject is null or v_subject !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  v_calendar := v_subject::uuid;
  return (
    select jsonb_build_object(
      'calendar', jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz"),
      'events', coalesce((
        select jsonb_agg(jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_start", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb)) order by e."starts_at")
        from "better_supabase"."calendar_events" e
        where e."calendar_id" = v_calendar
          and (e."rrule" is not null or e."ends_at" > now() - interval '1 year')
      ), '[]'::jsonb)
    )
    from "better_supabase"."calendars" k where k."id" = v_calendar and k."tenant_id"::text = v_tenant
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.calendar_free_busy (
  tenant      uuid,
  user_ids    uuid[],
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_window tstzrange;
begin
  if calendar_free_busy.range_start is null or calendar_free_busy.range_end is null
    or calendar_free_busy.range_end <= calendar_free_busy.range_start
    or calendar_free_busy.range_end - calendar_free_busy.range_start > interval '62 days' then
    raise exception 'the range must end after it starts and cover at most 62 days' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if coalesce(cardinality(calendar_free_busy.user_ids), 0) not between 1 and 100 then
    raise exception 'ask for 1 to 100 members' using errcode = '22023', hint = 'CALENDAR_RANGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', calendar_free_busy.tenant, 'calendar.read'), false)) then
    raise exception 'not allowed to read this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  v_window := tstzrange(calendar_free_busy.range_start, calendar_free_busy.range_end);
  return (
    with blocks as (
      select b.user_id, b.kind, tstzrange(b.starts_at, b.ends_at) * v_window as during
      from "better_supabase"."calendar_busy_blocks"(calendar_free_busy.tenant, calendar_free_busy.user_ids, calendar_free_busy.range_start, calendar_free_busy.range_end) b
    ),
  hours as (
    select h."user_id" as user_id, h."tz" as tz,
      tstzrange((d.day + h."starts_at") at time zone h."tz", (d.day + h."ends_at") at time zone h."tz") * v_window as during
    from "better_supabase"."calendar_working_hours" h
    cross join lateral generate_series(
      ((calendar_free_busy.range_start at time zone h."tz")::date - 1)::timestamp,
      ((calendar_free_busy.range_end at time zone h."tz")::date)::timestamp,
      interval '1 day'
    ) d (day)
    where h."tenant_id" = calendar_free_busy.tenant
      and h."user_id" = any (calendar_free_busy.user_ids)
      and extract(isodow from d.day) = h."weekday"
  ),
    members as (
      select m.user_id, min(m.ord) as ord
      from unnest(calendar_free_busy.user_ids) with ordinality m (user_id, ord)
      where m.user_id is not null
      group by m.user_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'userId', u.user_id,
      'busy', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id)) x), '[]'::jsonb),
      'outOfOffice', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'out_of_office')) x), '[]'::jsonb),
      'focusTime', coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(b.during) from blocks b where b.user_id = u.user_id and b.kind = 'focus_time')) x), '[]'::jsonb),
      'tz', (select min(w.tz) from hours w where w.user_id = u.user_id),
      'workingHours', case when exists (select 1 from hours w where w.user_id = u.user_id)
        then coalesce((select jsonb_agg(jsonb_build_object('startsAt', lower(x), 'endsAt', upper(x)) order by lower(x)) from unnest((select range_agg(w.during) from hours w where w.user_id = u.user_id)) x), '[]'::jsonb) end
    ) order by u.ord), '[]'::jsonb)
    from members u
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.calendar_rule_starts (
  dtstart     timestamp with time zone,
  tz          text,
  rrule       text,
  range_start timestamp with time zone,
  range_end   timestamp with time zone
)
  RETURNS SETOF timestamp WITH time zone
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
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
    v_until := (regexp_replace(v_parts ->> 'UNTIL', '^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2})Z$', '\1-\2-\3 \4:\5:\6+00'))::timestamptz;
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.data_lifecycle_tables()
  RETURNS TABLE (
    subject  text,
    name     text,
    tbl      text,
    col      text,
    purge    boolean,
    omit     text[],
    exported boolean
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select t.subject, t.name, t.tbl, t.col, t.purge,
    t.omit || array(
      select a.attname::text
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(t.tbl)
        and a.attnum > 0
        and not a.attisdropped
        and a.attname ~* 'token|secret|_hash|password|api_key|license_key'
        and a.attname <> t.col
        and not a.attname = any(t.omit)
      order by a.attnum
    ) as omit,
    t.exported
  from (
  select * from (values
    ('user', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'actor_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('user', 'public.memberships', '"public"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.profiles', '"better_supabase"."profiles"', 'id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_suppressions', '"better_supabase"."notification_suppressions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.user_settings', '"better_supabase"."user_settings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.comments', '"better_supabase"."comments"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.onboarding_progress', '"better_supabase"."onboarding_progress"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.waitlist_entries', '"better_supabase"."waitlist_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.invite_code_redemptions', '"better_supabase"."invite_code_redemptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.announcement_dismissals', '"better_supabase"."announcement_dismissals"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.streams', '"better_supabase"."streams"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definition_grants', '"better_supabase"."workflow_definition_grants"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_members', '"better_supabase"."inbox_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_team_members', '"better_supabase"."inbox_team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.contacts', '"better_supabase"."contacts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_participants', '"better_supabase"."conversation_participants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_reads', '"better_supabase"."conversation_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_mentions', '"better_supabase"."inbox_mentions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_messages', '"better_supabase"."ai_messages"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_runs', '"better_supabase"."ai_runs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_tool_approvals', '"better_supabase"."ai_tool_approvals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_pending_inputs', '"better_supabase"."ai_pending_inputs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_feedback', '"better_supabase"."ai_message_feedback"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_shares', '"better_supabase"."ai_chat_shares"', 'created_by', true, array['token_hash']::text[], true),
    ('user', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_run_steps', '"better_supabase"."ai_run_steps"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_harness_sessions', '"better_supabase"."ai_harness_sessions"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_document_versions', '"better_supabase"."ai_document_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agents', '"better_supabase"."agents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_ratings', '"better_supabase"."agent_ratings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.connector_sessions', '"better_supabase"."connector_sessions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.push_devices', '"better_supabase"."push_devices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.teams', '"better_supabase"."teams"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.team_members', '"better_supabase"."team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', false, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.engagements', '"better_supabase"."engagements"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'organization_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'organization_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.outbox_events', '"better_supabase"."outbox_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_events', '"better_supabase"."notification_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_deliveries', '"better_supabase"."notification_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_delivery_events', '"better_supabase"."notification_delivery_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comments', '"better_supabase"."comments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_domains', '"better_supabase"."organization_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.organization_sso_providers', '"better_supabase"."organization_sso_providers"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.onboarding_progress', '"better_supabase"."onboarding_progress"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invite_codes', '"better_supabase"."invite_codes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.streams', '"better_supabase"."streams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_credentials', '"better_supabase"."workflow_credentials"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.chat_installations', '"better_supabase"."chat_installations"', 'tenant_id', false, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.inboxes', '"better_supabase"."inboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_teams', '"better_supabase"."inbox_teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contacts', '"better_supabase"."contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contact_identities', '"better_supabase"."contact_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_events', '"better_supabase"."conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_messages', '"better_supabase"."inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_deliveries', '"better_supabase"."message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_mentions', '"better_supabase"."inbox_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbound_events', '"better_supabase"."inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.message_templates', '"better_supabase"."message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'organization_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agents', '"better_supabase"."agents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_cache_entries', '"better_supabase"."ai_cache_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_batch_items', '"better_supabase"."ai_batch_items"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shared_views', '"better_supabase"."shared_views"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.relations', '"better_supabase"."relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.products', '"better_supabase"."products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_options', '"better_supabase"."product_options"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_option_values', '"better_supabase"."product_option_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variants', '"better_supabase"."product_variants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_values', '"better_supabase"."product_variant_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.price_lists', '"better_supabase"."price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.categories', '"better_supabase"."categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collections', '"better_supabase"."collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.storefronts', '"better_supabase"."storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', false, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_locations', '"better_supabase"."inventory_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_levels', '"better_supabase"."stock_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_movements', '"better_supabase"."stock_movements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_reservations', '"better_supabase"."stock_reservations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfers', '"better_supabase"."stock_transfers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfer_lines', '"better_supabase"."stock_transfer_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_orders', '"better_supabase"."purchase_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_order_lines', '"better_supabase"."purchase_order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipping_rates', '"better_supabase"."shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillments', '"better_supabase"."fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillment_lines', '"better_supabase"."fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_returns', '"better_supabase"."order_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_return_lines', '"better_supabase"."order_return_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_refunds', '"better_supabase"."order_refunds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotions', '"better_supabase"."promotions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_codes', '"better_supabase"."promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_promotion_codes', '"better_supabase"."cart_promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_redemptions', '"better_supabase"."promotion_redemptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forms', '"better_supabase"."forms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.jobs', '"better_supabase"."jobs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipelines', '"better_supabase"."pipelines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stages', '"better_supabase"."pipeline_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_transitions', '"better_supabase"."pipeline_transitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.companies', '"better_supabase"."companies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.people', '"better_supabase"."people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.company_people', '"better_supabase"."company_people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_inbox_contacts', '"better_supabase"."person_inbox_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagements', '"better_supabase"."engagements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_payments', '"better_supabase"."invoice_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.targets', '"better_supabase"."targets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rules', '"better_supabase"."rules"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_versions', '"better_supabase"."rule_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_calendar_events (
  calendar_ids uuid[],
  range_start  timestamp with time zone,
  range_end    timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_start", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb)) order by e."starts_at", e."id"), '[]'::jsonb)
  from "better_supabase"."calendar_events" e
  where e."calendar_id" = any (list_calendar_events.calendar_ids)
    and e."starts_at" < list_calendar_events.range_end
    and (
      (e."rrule" is null and e."recurrence_id" is null and e."ends_at" > list_calendar_events.range_start)
      or e."rrule" is not null
      or (e."recurrence_id" is not null and (e."ends_at" > list_calendar_events.range_start or e."original_start" >= list_calendar_events.range_start - interval '1 year'))
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_calendar_working_hours (
  tenant   uuid,
  user_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('userId', w.user_id, 'tz', w.tz, 'hours', w.hours) order by w.user_id), '[]'::jsonb)
  from (
    select h."user_id" as user_id, min(h."tz") as tz,
      jsonb_agg(jsonb_build_object('weekday', h."weekday", 'start', to_char(h."starts_at", 'HH24:MI'), 'end', case when h."ends_at" = time '24:00' then '24:00' else to_char(h."ends_at", 'HH24:MI') end) order by h."weekday", h."starts_at") as hours
    from "better_supabase"."calendar_working_hours" h
    where h."tenant_id" = list_calendar_working_hours.tenant
      and (list_calendar_working_hours.user_ids is null or h."user_id" = any (list_calendar_working_hours.user_ids))
    group by h."user_id"
  ) w
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_booking_resource (
  tenant uuid,
  item   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_booking_resource.item, '{}'::jsonb);
  v_tenant uuid := save_booking_resource.tenant;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'bookings.manage'), false)) then
    raise exception 'not allowed to manage bookings' using errcode = '42501', hint = 'BOOKING_FORBIDDEN';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  if v_id is null then
    insert into "better_supabase"."booking_resources" ("tenant_id", "name", "kind", "capacity", "tz", "active", "calendar_id", "host_user_id", "check_busy")
    values (v_tenant, case when v_item ? 'name' then v_item ->> 'name' else null end, case when v_item ? 'kind' then v_item ->> 'kind' else 'staff' end, case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else 1 end, case when v_item ? 'tz' then v_item ->> 'tz' else 'UTC' end, case when v_item ? 'active' then (v_item ->> 'active')::boolean else true end, case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else null end, case when v_item ? 'hostUserId' then nullif(v_item ->> 'hostUserId', '')::uuid else null end, case when v_item ? 'checkBusy' then (v_item ->> 'checkBusy')::boolean else false end)
    returning "id" into v_id;
  else
    update "better_supabase"."booking_resources" set "name" = case when v_item ? 'name' then v_item ->> 'name' else "name" end, "kind" = case when v_item ? 'kind' then v_item ->> 'kind' else "kind" end, "capacity" = case when v_item ? 'capacity' then (v_item ->> 'capacity')::integer else "capacity" end, "tz" = case when v_item ? 'tz' then v_item ->> 'tz' else "tz" end, "active" = case when v_item ? 'active' then (v_item ->> 'active')::boolean else "active" end, "calendar_id" = case when v_item ? 'calendarId' then nullif(v_item ->> 'calendarId', '')::uuid else "calendar_id" end, "host_user_id" = case when v_item ? 'hostUserId' then nullif(v_item ->> 'hostUserId', '')::uuid else "host_user_id" end, "check_busy" = case when v_item ? 'checkBusy' then (v_item ->> 'checkBusy')::boolean else "check_busy" end
    where "id" = v_id and "tenant_id" = v_tenant;
    if not found then
      raise exception 'not found' using errcode = 'P0002', hint = 'BOOKING_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_calendar_event (
  calendar_id uuid,
  item        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_item jsonb := coalesce(save_calendar_event.item, '{}'::jsonb);
  v_tenant uuid;
  v_tz text;
  v_id uuid := nullif(v_item ->> 'id', '')::uuid;
  v_master uuid := nullif(v_item ->> 'recurrenceId', '')::uuid;
  v_uid text := nullif(v_item ->> 'uid', '');
  v_created boolean := false;
  v_exdates timestamptz[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "tz" into v_tenant, v_tz from "better_supabase"."calendars" where "id" = save_calendar_event.calendar_id;
  if not found then
    raise exception 'calendar not found' using errcode = 'P0002', hint = 'CALENDAR_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'calendar.write'), false)) then
    raise exception 'not allowed to change this calendar' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if v_item ? 'status' and v_item ->> 'status' not in ('confirmed', 'tentative', 'cancelled') then
    raise exception 'status must be confirmed, tentative or cancelled' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'kind' and v_item ->> 'kind' not in ('event', 'out_of_office', 'focus_time') then
    raise exception 'kind must be event, out_of_office or focus_time' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'transparency' and v_item ->> 'transparency' not in ('opaque', 'transparent') then
    raise exception 'transparency must be opaque or transparent' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  if v_item ? 'tz' and not exists (select 1 from pg_catalog.pg_timezone_names where name = v_item ->> 'tz') then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
  end if;
  select coalesce(array_agg(value::timestamptz order by value::timestamptz), '{}')
    into v_exdates from jsonb_array_elements_text(coalesce(v_item -> 'exdates', '[]'::jsonb));
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_calendar_event_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using v_tenant, save_calendar_event.calendar_id, v_item;
    end if;
  end;
  if v_id is null then
    if v_master is not null then
      select "uid" into v_uid from "better_supabase"."calendar_events"
        where "id" = v_master and "calendar_id" = save_calendar_event.calendar_id and "recurrence_id" is null and "rrule" is not null;
      if not found or v_item ->> 'originalStart' is null then
        raise exception 'an override needs a recurring event and an originalStart' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
      end if;
    end if;
    if v_item ->> 'startsAt' is null or v_item ->> 'endsAt' is null then
      raise exception 'an event needs startsAt and endsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
    end if;
    v_id := gen_random_uuid();
    v_uid := coalesce(v_uid, v_id::text);
    insert into "better_supabase"."calendar_events" ("id", "tenant_id", "calendar_id", "uid", "recurrence_id", "original_start", "title", "starts_at", "ends_at", "all_day", "tz", "status", "rrule", "exdates", "description", "location", "color", "kind", "transparency", "auto_decline", "subject_type", "subject_id", "created_by")
    values (v_id, v_tenant, save_calendar_event.calendar_id, v_uid, v_master, (v_item ->> 'originalStart')::timestamptz, coalesce(v_item ->> 'title', ''), (v_item ->> 'startsAt')::timestamptz, (v_item ->> 'endsAt')::timestamptz, coalesce((v_item ->> 'allDay')::boolean, false), coalesce(v_item ->> 'tz', v_tz), coalesce(v_item ->> 'status', 'confirmed'), nullif(v_item ->> 'rrule', ''), v_exdates, v_item ->> 'description', v_item ->> 'location', v_item ->> 'color', coalesce(v_item ->> 'kind', 'event'), coalesce(v_item ->> 'transparency', 'opaque'), coalesce((v_item ->> 'autoDecline')::boolean, false), v_item ->> 'subjectType', v_item ->> 'subjectId', auth.uid());
    v_created := true;
  else
    update "better_supabase"."calendar_events" set
    "title" = case when v_item ? 'title' then coalesce(v_item ->> 'title', '') else "title" end,
    "starts_at" = case when v_item ? 'startsAt' then (v_item ->> 'startsAt')::timestamptz else "starts_at" end,
    "ends_at" = case when v_item ? 'endsAt' then (v_item ->> 'endsAt')::timestamptz else "ends_at" end,
    "all_day" = case when v_item ? 'allDay' then coalesce((v_item ->> 'allDay')::boolean, false) else "all_day" end,
    "tz" = case when v_item ? 'tz' then coalesce(v_item ->> 'tz', v_tz) else "tz" end,
    "status" = case when v_item ? 'status' then coalesce(v_item ->> 'status', 'confirmed') else "status" end,
    "rrule" = case when v_item ? 'rrule' then nullif(v_item ->> 'rrule', '') else "rrule" end,
    "description" = case when v_item ? 'description' then v_item ->> 'description' else "description" end,
    "location" = case when v_item ? 'location' then v_item ->> 'location' else "location" end,
    "color" = case when v_item ? 'color' then v_item ->> 'color' else "color" end,
    "kind" = case when v_item ? 'kind' then coalesce(v_item ->> 'kind', 'event') else "kind" end,
    "transparency" = case when v_item ? 'transparency' then coalesce(v_item ->> 'transparency', 'opaque') else "transparency" end,
    "auto_decline" = case when v_item ? 'autoDecline' then coalesce((v_item ->> 'autoDecline')::boolean, false) else "auto_decline" end,
    "subject_type" = case when v_item ? 'subjectType' then v_item ->> 'subjectType' else "subject_type" end,
    "subject_id" = case when v_item ? 'subjectId' then v_item ->> 'subjectId' else "subject_id" end,
    "exdates" = case when v_item ? 'exdates' then v_exdates else "exdates" end,
    "updated_at" = now()
    where "id" = v_id and "calendar_id" = save_calendar_event.calendar_id
    returning "uid" into v_uid;
    if not found then
      raise exception 'event not found' using errcode = 'P0002', hint = 'CALENDAR_EVENT_NOT_FOUND';
    end if;
  end if;
  if exists (select 1 from "better_supabase"."calendar_events" where "id" = v_id and "ends_at" < "starts_at") then
    raise exception 'endsAt must not be before startsAt' using errcode = '22023', hint = 'CALENDAR_EVENT_INVALID';
  end if;
  insert into "better_supabase"."recurrence_rules" ("tenant_id", "subject_type", "subject_id", "dtstart", "tzid", "rrule")
  select e."tenant_id", 'calendar_event', e."id"::text, e."starts_at", e."tz", coalesce(e."rrule", 'FREQ=DAILY;COUNT=1')
  from "better_supabase"."calendar_events" e where e."id" = v_id
  on conflict ("tenant_id", "subject_type", "subject_id")
  do update set "dtstart" = excluded."dtstart", "tzid" = excluded."tzid", "rrule" = excluded."rrule";
  if v_created then
    perform "better_supabase".emit_event('calendar_event.created', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', save_calendar_event.calendar_id), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  else
    perform "better_supabase".emit_event('calendar_event.updated', jsonb_build_object('organizationId', v_tenant, 'id', v_id, 'calendarId', save_calendar_event.calendar_id), 'calendar-events/' || v_id::text, (v_tenant)::text, null, 'better-supabase/calendar');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_calendar_event_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'uid', v_uid, 'created', v_created);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_calendar_working_hours (
  tenant  uuid,
  user_id uuid,
  tz      text,
  hours   jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_user uuid := coalesce(set_calendar_working_hours.user_id, auth.uid());
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in or pass a user id' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not (
    (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.manage'), false))
    or (v_user = auth.uid() and coalesce(better_supabase.can('tenant', set_calendar_working_hours.tenant, 'calendar.read'), false))
  ) then
    raise exception 'not allowed to set these working hours' using errcode = '42501', hint = 'CALENDAR_FORBIDDEN';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = coalesce(set_calendar_working_hours.tz, 'UTC')) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'CALENDAR_TZ_INVALID';
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
    raise exception 'hours must be [{ weekday 1-7, start HH:MM, end HH:MM }] with end after start' using errcode = '22023', hint = 'CALENDAR_HOURS_INVALID';
  end if;
  delete from "better_supabase"."calendar_working_hours" where "tenant_id" = set_calendar_working_hours.tenant and "user_id" = v_user;
  insert into "better_supabase"."calendar_working_hours" ("tenant_id", "user_id", "weekday", "starts_at", "ends_at", "tz")
  select distinct set_calendar_working_hours.tenant, v_user, (x ->> 'weekday')::smallint, (x ->> 'start')::time, (x ->> 'end')::time, coalesce(set_calendar_working_hours.tz, 'UTC')
  from jsonb_array_elements(coalesce(set_calendar_working_hours.hours, '[]'::jsonb)) x;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

ALTER TABLE "better_supabase"."calendar_events"
  ADD CONSTRAINT "calendar_events_kind_check" CHECK ((kind = ANY (ARRAY['event'::text, 'out_of_office'::text, 'focus_time'::text])));

ALTER TABLE "better_supabase"."calendar_events"
  ADD CONSTRAINT "calendar_events_transparency_check" CHECK ((transparency = ANY (ARRAY['opaque'::text, 'transparent'::text])));

CREATE TRIGGER calendar_attendees_auto_decline
  BEFORE INSERT OR UPDATE OF user_id ON better_supabase.calendar_attendees
  FOR EACH ROW
  WHEN (((new.user_id IS NOT NULL) AND (new.response = 'needs-action'::text)))
  EXECUTE FUNCTION better_supabase.calendar_attendee_auto_decline();

CREATE TRIGGER calendar_events_auto_decline
  AFTER INSERT OR UPDATE OF starts_at, ends_at, kind, auto_decline, status ON better_supabase.calendar_events
  FOR EACH ROW
  WHEN (((new.kind <> 'event'::text) AND new.auto_decline AND (new.status <> 'cancelled'::text) AND (new.rrule IS NULL)))
  EXECUTE FUNCTION better_supabase.calendar_block_auto_decline();

CREATE POLICY "calendar_working_hours_read" ON "better_supabase"."calendar_working_hours"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)) OR (user_id = ( SELECT auth.uid() AS uid))));

REVOKE ALL ON FUNCTION "api"."calendar_busy_blocks"(uuid, uuid[], timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."calendar_busy_blocks"(uuid, uuid[], timestamp WITH time zone, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."calendar_free_busy"(uuid, uuid[], timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."calendar_free_busy"(uuid, uuid[], timestamp WITH time zone, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."calendar_rule_starts"(timestamp WITH time zone, text, text, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."calendar_rule_starts"(timestamp WITH time zone, text, text, timestamp WITH time zone, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_calendar_working_hours"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_calendar_working_hours"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_calendar_working_hours"(uuid, uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_calendar_working_hours"(uuid, uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."calendar_attendee_auto_decline"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."calendar_block_auto_decline"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."calendar_busy_blocks"(uuid, uuid[], timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."calendar_busy_blocks"(uuid, uuid[], timestamp WITH time zone, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."calendar_free_busy"(uuid, uuid[], timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."calendar_free_busy"(uuid, uuid[], timestamp WITH time zone, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."calendar_rule_starts"(timestamp WITH time zone, text, text, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."calendar_rule_starts"(timestamp WITH time zone, text, text, timestamp WITH time zone, timestamp WITH time zone)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_calendar_working_hours"(uuid, uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_calendar_working_hours"(uuid, uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_calendar_working_hours"(uuid, uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_calendar_working_hours"(uuid, uuid, text, jsonb) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."calendar_working_hours" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."calendar_working_hours" TO "service_role";
