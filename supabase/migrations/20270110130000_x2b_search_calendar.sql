SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.calendar_bootstrap (
  tenant         uuid,
  range_start    timestamp with time zone,
  range_end      timestamp with time zone,
  upcoming_start timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  upcoming_end   timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."calendar_bootstrap"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION better_supabase.calendar_bootstrap (
  tenant         uuid,
  range_start    timestamp with time zone,
  range_end      timestamp with time zone,
  upcoming_start timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  upcoming_end   timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_calendars jsonb := "better_supabase"."list_calendars"(calendar_bootstrap.tenant);
  v_ids uuid[];
  v_events jsonb := '[]'::jsonb;
  v_upcoming jsonb := '[]'::jsonb;
  v_reminders jsonb := '[]'::jsonb;
begin
  select coalesce(array_agg((c ->> 'id')::uuid), '{}'::uuid[]) into v_ids
    from jsonb_array_elements(v_calendars) c;
  if cardinality(v_ids) > 0 then
    v_events := "better_supabase"."list_calendar_events"(v_ids, calendar_bootstrap.range_start, calendar_bootstrap.range_end);
    if calendar_bootstrap.upcoming_start is not null and calendar_bootstrap.upcoming_end is not null then
      v_upcoming := "better_supabase"."list_calendar_events"(v_ids, calendar_bootstrap.upcoming_start, calendar_bootstrap.upcoming_end);
    end if;
  -- list_my_reminders needs reminders.manage; a caller without it gets none.
  begin
    v_reminders := "better_supabase"."list_my_reminders"(calendar_bootstrap.tenant, 'calendar_event', null);
  exception when insufficient_privilege then
    v_reminders := '[]'::jsonb;
  end;
  end if;
  return jsonb_build_object('calendarList', v_calendars, 'monthEvents', v_events, 'upcomingEvents', v_upcoming, 'myReminders', v_reminders);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search (
  q           text,
  types       text[]  DEFAULT NULL::text[],
  tenant      uuid    DEFAULT NULL::uuid,
  max_results integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_q text := btrim(coalesce(search.q, ''));
  v_norm text;
  v_web tsquery;
  v_prefix tsquery;
  v_limit integer := least(greatest(coalesce(search.max_results, 20), 1), 100);
  v_pool integer;
begin
  if length(v_q) > 256 then
    raise exception 'a search query is at most 256 characters' using errcode = '22023', hint = 'SEARCH_QUERY_TOO_LONG';
  end if;
  if v_q = '' then
    return '[]'::jsonb;
  end if;
  v_pool := v_limit * 5;
  v_norm := "better_supabase"."search_normalize"(v_q);
  v_web := websearch_to_tsquery('simple', v_norm);
  select to_tsquery('simple', string_agg(quote_literal(w) || ':*', ' & '))
    into v_prefix
    from regexp_split_to_table(v_norm, '[^[:alnum:]]+') w
    where w <> '';
  return coalesce((
    with text_hits as materialized (
      select h.subject_type, h.subject_id, h.score,
        row_number() over (order by h.score desc) as rank
      from (
        select d."subject_type" as subject_type, d."subject_id" as subject_id,
          -- A row only the trigram index matched has no rank to compute.
          case when d."tsv" @@ v_web or (v_prefix is not null and d."tsv" @@ v_prefix)
            then 2 * coalesce(ts_rank_cd(d."tsv", v_web), 0)
              + coalesce(ts_rank_cd(d."tsv", v_prefix), 0)
            else 0
          end + extensions.similarity(d."title_search", v_norm) as score
        from "better_supabase"."search_documents" d
        where (search.types is null or d."subject_type" = any (search.types))
          and (search.tenant is null or d."tenant_id" = search.tenant)
          and (d."tsv" @@ v_web
            or (v_prefix is not null and d."tsv" @@ v_prefix)
            or d."title_search" operator(extensions.%) v_norm)
        order by score desc
        limit v_pool
      ) h
    ),
    fused as (
      select t.subject_type, t.subject_id, t.score from text_hits t
    ),
    visible as (
      select d."tenant_id" as tenant, d."subject_type" as subject_type, d."subject_id" as subject_id,
        d."title" as title, d."url" as url, d."body" as body, f.score
      from fused f
      join "better_supabase"."search_documents" d on d."subject_type" = f.subject_type and d."subject_id" = f.subject_id
      where "better_supabase"."can_subject"(f.subject_type, f.subject_id, 'read')
      order by f.score desc, f.subject_type, f.subject_id
      limit v_limit
    )
    select jsonb_agg(jsonb_build_object(
      'organizationId', v.tenant,
      'subjectType', v.subject_type,
      'subjectId', v.subject_id,
      'title', v.title,
      'url', v.url,
      'snippet', case when v.body is null then null
        else ts_headline('simple', v.body, coalesce(v_prefix, v_web), 'StartSel="", StopSel="", MaxWords=20, MinWords=8, MaxFragments=1')
      end,
      'score', round(v.score::numeric, 6)
    ) order by v.score desc, v.subject_type, v.subject_id)
    from visible v
  ), '[]'::jsonb);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."calendar_bootstrap"(uuid, timestamp WITH time zone, timestamp WITH time zone, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."calendar_bootstrap"(uuid, timestamp WITH time zone, timestamp WITH time zone, timestamp WITH time zone, timestamp WITH time zone)
  TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "better_supabase"."calendar_bootstrap"(uuid, timestamp WITH time zone, timestamp WITH time zone, timestamp WITH time zone, timestamp WITH time zone)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."calendar_bootstrap"(uuid, timestamp WITH time zone, timestamp WITH time zone, timestamp WITH time zone, timestamp WITH time zone)
  TO "authenticated", "service_role";
