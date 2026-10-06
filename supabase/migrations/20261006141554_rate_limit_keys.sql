SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.hit_rate_limit (
  scope        text,
  key          text,
  max_requests integer  DEFAULT NULL::integer,
  period       interval DEFAULT NULL::interval
)
  RETURNS TABLE (
    allowed     boolean,
    remaining   integer,
    retry_after integer
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  rule better_supabase.rate_limit_rules;
  limit_max integer;
  limit_period interval;
  used integer;
  started timestamptz;
begin
  select * into rule from better_supabase.rate_limit_rules r where r.scope = hit_rate_limit.scope;
  limit_max := coalesce(max_requests, rule.max_requests);
  limit_period := coalesce(period, rule.period);
  if limit_max is null or limit_period is null then
    raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', scope
      using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
  end if;
  insert into better_supabase.rate_limits as l (scope, key, window_start, hits)
  values (scope, key, now(), 1)
  on conflict on constraint rate_limits_pkey do update set
    window_start = case when l.window_start + limit_period <= now() then now() else l.window_start end,
    hits = case when l.window_start + limit_period <= now() then 1 else l.hits + 1 end
  returning l.hits, l.window_start into used, started;
  return query select
    used <= limit_max,
    greatest(limit_max - used, 0),
    case when used <= limit_max then 0
      else greatest(1, ceil(extract(epoch from started + limit_period - now()))::integer) end;
end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_rate_limits (
  batch integer DEFAULT 10000
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with expired as (
    select l.scope, l.key from better_supabase.rate_limits l
    left join better_supabase.rate_limit_rules r on r.scope = l.scope
    where (r.scope is null and l.window_start < now() - interval '1 day')
      or l.window_start + r.period <= now()
    limit batch
  ),
  purged as (
    delete from better_supabase.rate_limits l
    using expired e
    where l.scope = e.scope and l.key = e.key
    returning 1
  )
  select count(*)::integer from purged
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."hit_rate_limit"(text, text, integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."hit_rate_limit"(text, text, integer, interval) TO "service_role";
