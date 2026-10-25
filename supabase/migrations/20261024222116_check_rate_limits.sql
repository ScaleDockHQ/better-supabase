SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.check_rate_limits (
  hits jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  total integer;
  scopes text[] := '{}';
  keys text[] := '{}';
  maxes integer[] := '{}';
  periods interval[] := '{}';
  used integer[] := '{}';
  starts timestamptz[] := '{}';
  hit jsonb;
  rule better_supabase.rate_limit_rules;
  counter better_supabase.rate_limits;
  limit_max integer;
  limit_period interval;
  current_hits integer;
  first_blocked integer;
  longest integer := 0;
  passed boolean;
  results jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(hits) is distinct from 'array' or jsonb_array_length(hits) = 0 then
    raise exception 'check_rate_limits needs a non-empty array of hits'
      using errcode = '22023', hint = 'RATE_LIMIT_HITS';
  end if;
  total := jsonb_array_length(hits);
  for i in 1 .. total loop
    hit := hits -> (i - 1);
    if coalesce(hit ->> 'scope', '') = '' or (hit ->> 'key') is null then
      raise exception 'Hit % of check_rate_limits needs a scope and a key', i - 1
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    select * into rule from better_supabase.rate_limit_rules r where r.scope = hit ->> 'scope';
    limit_max := coalesce((hit ->> 'max_requests')::integer, rule.max_requests);
    limit_period := coalesce((hit ->> 'period')::interval, rule.period);
    if limit_max is null or limit_period is null then
      raise exception 'No rate limit for %: call set_rate_limit or pass max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_UNKNOWN';
    end if;
    if limit_max < 1 or limit_period <= interval '0' then
      raise exception 'The rate limit for % needs a positive max_requests and period', hit ->> 'scope'
        using errcode = '22023', hint = 'RATE_LIMIT_HITS';
    end if;
    for j in 1 .. i - 1 loop
      if scopes[j] = hit ->> 'scope' and keys[j] = hit ->> 'key' then
        raise exception 'Hits % and % of check_rate_limits count the same scope % and key; give each limit its own scope', j - 1, i - 1, hit ->> 'scope'
          using errcode = '22023', hint = 'RATE_LIMIT_HITS';
      end if;
    end loop;
    scopes := scopes || (hit ->> 'scope');
    keys := keys || (hit ->> 'key');
    maxes := maxes || limit_max;
    periods := periods || limit_period;
  end loop;

  insert into better_supabase.rate_limits as l (scope, key, window_start, hits, period)
  select u.scope, u.key, now(), 0, u.period
  from unnest(scopes, keys, periods) as u(scope, key, period)
  order by u.scope, u.key
  on conflict on constraint rate_limits_pkey do nothing;

  perform 1
  from better_supabase.rate_limits l
  join unnest(scopes, keys) as u(scope, key) on l.scope = u.scope and l.key = u.key
  order by l.scope, l.key
  for update of l;

  for i in 1 .. total loop
    select * into counter from better_supabase.rate_limits l
    where l.scope = scopes[i] and l.key = keys[i];
    if counter.window_start + periods[i] <= now() then
      used := used || 0;
      starts := starts || now();
    else
      used := used || counter.hits;
      starts := starts || counter.window_start;
    end if;
    if used[i] + 1 > maxes[i] then
      longest := greatest(longest, greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer));
      first_blocked := coalesce(first_blocked, i - 1);
    end if;
  end loop;

  passed := first_blocked is null;

  if passed then
    for i in 1 .. total loop
      update better_supabase.rate_limits l set
        window_start = starts[i],
        hits = used[i] + 1,
        period = periods[i]
      where l.scope = scopes[i] and l.key = keys[i];
    end loop;
  end if;

  for i in 1 .. total loop
    current_hits := used[i] + case when passed then 1 else 0 end;
    results := results || jsonb_build_array(jsonb_build_object(
      'allowed', used[i] + 1 <= maxes[i],
      'remaining', greatest(maxes[i] - current_hits, 0),
      'retry_after', case when used[i] + 1 <= maxes[i] then 0
        else greatest(1, ceil(extract(epoch from starts[i] + periods[i] - now()))::integer) end
    ));
  end loop;

  return jsonb_build_object(
    'allowed', passed,
    'blocked', first_blocked,
    'retry_after', longest,
    'results', results
  );
end
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."check_rate_limits"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."check_rate_limits"(jsonb) TO "service_role";
