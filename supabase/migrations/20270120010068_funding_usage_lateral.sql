SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.funding_award_usage (
  award_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'awardId', a."id",
    'units', a."units",
    'period', a."period",
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'start', s.start,
        'end', nullif(s.finish, 'infinity'::date) - 1,
        'awarded', a."units",
        'used', s.used,
        'over', greatest(s.used - a."units", 0),
        'under', greatest(a."units" - s.used, 0)
      ) order by s.start)
      from (
        select g.start, (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end) as finish, u.used
        from (
          select pg_catalog.generate_series(
            (case a."period" when 'week' then date_trunc('week', a."starts_on")::date when 'month' then date_trunc('month', a."starts_on")::date else a."starts_on" end)::timestamp,
            coalesce(a."ends_on", current_date)::timestamp,
            case a."period" when 'week' then interval '1 week' else interval '1 month' end
          )::date as start
          where a."period" <> 'total'
          union all
          select a."starts_on" where a."period" = 'total'
        ) g
        -- A lateral aggregate: a scalar subquery in the select list is copied into
        -- every reference of `s.used` when the planner flattens `s`, which ran the
        -- deliveries policy three times per period.
        cross join lateral (
          select coalesce(sum(x."units"), 0) as used from "better_supabase"."funding_deliveries" x
          where x."tenant_id" = a."tenant_id" and x."award_id" = a."id" and x."status" <> 'rejected'
            and x."delivered_on" >= g.start and x."delivered_on" < (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end)
        ) u
      ) s
    ), '[]'::jsonb)
  )
  from "better_supabase"."funding_awards" a
  where a."id" = funding_award_usage.award_id
$function$;
