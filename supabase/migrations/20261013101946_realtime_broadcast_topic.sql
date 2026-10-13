SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.broadcast_topic()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  rec jsonb := to_jsonb(case when tg_op = 'DELETE' then old else new end);
  topic text;
  event text := tg_op;
  private boolean := true;
  placeholder text;
  value text;
begin
  if tg_level <> 'ROW' then
    raise exception 'better_supabase.broadcast_topic() runs for each row'
      using errcode = '39P01';
  end if;
  if tg_nargs = 0 or tg_argv[0] = '' then
    raise exception 'better_supabase.broadcast_topic() needs the topic as its first argument'
      using errcode = '39P01';
  end if;
  topic := tg_argv[0];
  if tg_nargs > 1 and tg_argv[1] <> '' then event := tg_argv[1]; end if;
  if tg_nargs > 2 then private := tg_argv[2]::boolean; end if;
  for placeholder in select distinct m[1] from regexp_matches(tg_argv[0], '\{([^}]+)\}', 'g') as m loop
    if not rec ? placeholder then
      raise exception '%.% has no column % for the topic %', tg_table_schema, tg_table_name, placeholder, tg_argv[0]
        using errcode = '42703';
    end if;
    value := rec ->> placeholder;
    if value is null then
      return null;
    end if;
    if value !~ '^[\w.@+=-]+$' then
      raise exception 'topic value % of %.%.% contains characters topics do not allow', value, tg_table_schema, tg_table_name, placeholder
        using errcode = '22023';
    end if;
    topic := replace(topic, '{' || placeholder || '}', value);
  end loop;
  perform realtime.send(
    jsonb_build_object('old_record', old, 'record', new, 'operation', tg_op, 'table', tg_table_name, 'schema', tg_table_schema),
    event, topic, private
  );
  return null;
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."broadcast_topic"() FROM PUBLIC;
