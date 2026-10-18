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
  mode text := 'keys';
  placeholder text;
  param text;
  col text;
  value text;
  vals jsonb := '{}';
  keys text[];
  id jsonb;
begin
  if tg_level <> 'ROW' then
    raise exception 'better_supabase.broadcast_topic() runs for each row'
      using errcode = '39P01';
  end if;
  if tg_when <> 'AFTER' then
    raise exception 'better_supabase.broadcast_topic() runs after the write; as a % trigger it would cancel the write', lower(tg_when)
      using errcode = '39P01';
  end if;
  if tg_nargs = 0 or tg_argv[0] = '' then
    raise exception 'better_supabase.broadcast_topic() needs the topic as its first argument'
      using errcode = '39P01';
  end if;
  topic := tg_argv[0];
  if tg_nargs > 1 and tg_argv[1] <> '' then event := tg_argv[1]; end if;
  if tg_nargs > 2 and tg_argv[2] <> '' then private := tg_argv[2]::boolean; end if;
  if tg_nargs > 3 and tg_argv[3] <> '' then mode := tg_argv[3]; end if;
  if mode not in ('keys', 'row') then
    raise exception 'better_supabase.broadcast_topic() payload must be keys or row, not %', mode
      using errcode = '22023';
  end if;
  for placeholder in select distinct m[1] from regexp_matches(tg_argv[0], '\{([^}]+)\}', 'g') as m loop
    param := split_part(placeholder, '=', 1);
    col := coalesce(nullif(split_part(placeholder, '=', 2), ''), param);
    if not rec ? col then
      raise exception '%.% has no column % for the topic %', tg_table_schema, tg_table_name, col, tg_argv[0]
        using errcode = '42703';
    end if;
    value := rec ->> col;
    if value is null then
      return null;
    end if;
    if value !~ '^[\w.@+=-]+$' then
      raise warning 'skipped the broadcast on %: topic value % of %.%.% contains characters topics do not allow', tg_argv[0], value, tg_table_schema, tg_table_name, col;
      return null;
    end if;
    vals := vals || jsonb_build_object(param, value);
    topic := replace(topic, '{' || placeholder || '}', value);
  end loop;
  if mode = 'row' then
    perform realtime.send(
      jsonb_build_object('old_record', old, 'record', new, 'operation', tg_op, 'table', tg_table_name, 'schema', tg_table_schema),
      event, topic, private
    );
    return null;
  end if;
  select array_agg(a.attname::text order by array_position(i.indkey::int2[], a.attnum))
    into keys
    from pg_catalog.pg_index i
    join pg_catalog.pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey::int2[])
    where i.indrelid = tg_relid and i.indisprimary;
  id := case
    when keys is null then null
    when cardinality(keys) = 1 then rec -> keys[1]
    else (select jsonb_object_agg(k, rec -> k) from unnest(keys) as k)
  end;
  perform realtime.send(
    jsonb_build_object('operation', tg_op, 'schema', tg_table_schema, 'table', tg_table_name, 'id', id, 'values', vals),
    event, topic, private
  );
  return null;
end;
$function$;
