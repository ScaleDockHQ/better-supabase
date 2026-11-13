SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.booking_series_starts (
  rule        jsonb,
  first_start timestamp with time zone,
  tz          text
)
  RETURNS SETOF timestamp WITH time zone
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_freq text := booking_series_starts.rule ->> 'freq';
  v_interval integer;
  v_days integer[];
  v_count integer;
  v_until timestamptz;
  v_rrule text;
begin
  if jsonb_typeof(booking_series_starts.rule) is distinct from 'object' or v_freq is null or v_freq not in ('daily', 'weekly') then
    raise exception 'rule.freq is daily or weekly' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = booking_series_starts.tz) then
    raise exception 'tz must be an IANA time zone' using errcode = '22023', hint = 'BOOKING_TZ_INVALID';
  end if;
  begin
    v_interval := coalesce((booking_series_starts.rule ->> 'interval')::integer, 1);
    v_count := (booking_series_starts.rule ->> 'count')::integer;
    v_until := (booking_series_starts.rule ->> 'until')::timestamptz;
    v_days := array(select jsonb_array_elements_text(coalesce(booking_series_starts.rule -> 'weekdays', '[]'::jsonb))::integer);
  exception when others then
    raise exception 'rule.interval and rule.count are integers, rule.until a timestamp and rule.weekdays a list of 1 to 7' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end;
  if v_interval not between 1 and 52 then
    raise exception 'rule.interval is between 1 and 52' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if v_count is null and v_until is null then
    raise exception 'a rule needs count or until' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if v_count is not null and v_count not between 1 and 366 then
    raise exception 'rule.count is between 1 and 366' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if v_until is not null and v_until < booking_series_starts.first_start then
    raise exception 'rule.until is before the first occurrence' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  if exists (select 1 from unnest(v_days) d where d not between 1 and 7) then
    raise exception 'rule.weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'BOOKING_RULE_INVALID';
  end if;
  v_rrule := 'FREQ=' || upper(v_freq) || ';INTERVAL=' || v_interval::text;
  if v_freq = 'weekly' and cardinality(v_days) > 0 then
    v_rrule := v_rrule || ';BYDAY=' || (select string_agg((array['MO','TU','WE','TH','FR','SA','SU'])[d], ',' order by d) from (select distinct d from unnest(v_days) d) days);
  end if;
  if v_count is not null then
    v_rrule := v_rrule || ';COUNT=' || v_count::text;
  end if;
  return query select o from better_supabase.rrule_occurrences(v_rrule, booking_series_starts.first_start, booking_series_starts.tz, tstzrange(booking_series_starts.first_start, booking_series_starts.first_start + interval '730 days', '[)')) o
    where v_until is null or o <= v_until
    order by o
    limit 366;
end;
$function$;
