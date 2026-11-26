SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.read_batch (
  calls jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."read_batch"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.read_batch (
  calls jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_target constant text := 'api';
  v_call jsonb;
  v_fn text;
  v_args jsonb;
  v_proc record;
  v_found boolean;
  v_params text;
  v_columns text;
  v_value jsonb;
  v_state text;
  v_message text;
  v_detail text;
  v_hint text;
  v_out jsonb := '[]'::jsonb;
begin
  if jsonb_typeof($1) is distinct from 'array' then
    raise exception 'Pass read_batch an array of { fn, args }' using errcode = '22023', hint = 'READ_BATCH_INVALID';
  end if;
  if jsonb_array_length($1) > 50 then
    raise exception 'a batch runs at most 50 calls' using errcode = '54000', hint = 'READ_BATCH_TOO_LARGE';
  end if;
  for v_call in
    select e.value from jsonb_array_elements($1) with ordinality as e(value, n) order by e.n
  loop
    v_fn := case when jsonb_typeof(v_call) = 'object' then v_call ->> 'fn' end;
    v_args := case when jsonb_typeof(v_call) = 'object' then coalesce(v_call -> 'args', '{}'::jsonb) end;
    v_found := false;
    if v_fn is not null and v_fn <> 'read_batch' and jsonb_typeof(v_args) = 'object' then
      select p.proargnames, p.proargtypes, p.pronargs, p.pronargdefaults into v_proc
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = v_target
        and p.proname = v_fn
        and p.prokind = 'f'
        and p.provolatile in ('s', 'i')
        and not p.proretset
        and p.provariadic = 0
        and p.proargmodes is null
        and p.prorettype = 'pg_catalog.jsonb'::pg_catalog.regtype
        and (p.pronargs = 0 or p.proargnames is not null)
        and not exists (
          select 1 from jsonb_object_keys(v_args) k(arg)
          where k.arg = '' or not k.arg = any (coalesce(p.proargnames[1:p.pronargs], '{}'::text[]))
        )
        and not exists (
          select 1 from unnest(p.proargnames[1:p.pronargs - p.pronargdefaults]) r(arg)
          where not v_args ? r.arg
        )
      order by p.pronargs
      limit 1;
      v_found := found;
    end if;
    if not v_found then
      v_out := v_out || jsonb_build_array(jsonb_build_object('skipped', true));
      continue;
    end if;
    select
      string_agg(format('%I => a.%I', a.arg, a.arg), ', ' order by a.n),
      string_agg(format('%I %s', a.arg, pg_catalog.format_type(v_proc.proargtypes[(a.n - 1)::integer], null)), ', ' order by a.n)
    into v_params, v_columns
    from unnest(v_proc.proargnames[1:v_proc.pronargs]) with ordinality as a(arg, n)
    where v_args ? a.arg;
    begin
      if v_params is null then
        execute format('select to_jsonb(%I.%I())', v_target, v_fn) into v_value;
      else
        execute format('select to_jsonb(%I.%I(%s)) from jsonb_to_record($1) as a(%s)', v_target, v_fn, v_params, v_columns)
          into v_value using v_args;
      end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object('data', v_value));
    exception when others then
      get stacked diagnostics
        v_state = returned_sqlstate,
        v_message = message_text,
        v_detail = pg_exception_detail,
        v_hint = pg_exception_hint;
      v_out := v_out || jsonb_build_array(jsonb_build_object('error', jsonb_strip_nulls(jsonb_build_object(
        'code', v_state,
        'message', v_message,
        'details', nullif(v_detail, ''),
        'hint', nullif(v_hint, '')
      ))));
    end;
  end loop;
  return v_out;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."read_batch"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."read_batch"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."read_batch"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."read_batch"(jsonb) TO "authenticated", "service_role";
