CREATE OR REPLACE FUNCTION api.audit_entries_correlated (
  correlation text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."audit_entries_correlated"($1) $function$;

CREATE OR REPLACE FUNCTION api.audit_revert_source (
  entries text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."audit_revert_source"($1) $function$;

CREATE OR REPLACE FUNCTION api.revert_audit_entries (
  entries text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."revert_audit_entries"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_entries_correlated (
  correlation text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(l."id"::text order by l."id"), '[]'::jsonb)
  from "better_supabase"."audit_events" l
  where l."correlation_id" = audit_entries_correlated.correlation
    and l."actor_id" is not distinct from auth.uid();
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_revert_source (
  entries text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  found_entries jsonb;
begin
  if cardinality(audit_revert_source.entries) > 1000 then
    raise exception 'revert at most 1000 entries at once' using errcode = '22023', hint = 'AUDIT_REVERT_TOO_MANY';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', l."id"::text,
      'table', to_regclass(quote_ident(split_part(l."table_name", '.', 1)) || '.' || quote_ident(split_part(l."table_name", '.', 2)))::text,
      'op', l."op",
      'old', l."old_record",
      'new', l."new_record",
      'changed', to_jsonb(l."changed"),
      'keys', to_jsonb(coalesce(
        (select a.key_columns from better_supabase.audited_tables a where a.target = to_regclass(quote_ident(split_part(l."table_name", '.', 1)) || '.' || quote_ident(split_part(l."table_name", '.', 2)))),
        (select array_agg(att.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute att on att.attrelid = i.indrelid and att.attnum = k.attnum
         where i.indrelid = to_regclass(quote_ident(split_part(l."table_name", '.', 1)) || '.' || quote_ident(split_part(l."table_name", '.', 2))) and i.indisprimary)
      ))
    ) order by l."occurred_at" desc, l."id" desc), '[]'::jsonb)
  into found_entries
  from "better_supabase"."audit_events" l
  
  where l."id"::text = any (audit_revert_source.entries)
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or (l."organization_id" is not null and coalesce(better_supabase.member_can(auth.uid(), l."organization_id", 'audit.revert'), false)));
  if jsonb_array_length(found_entries) <> cardinality(array(select distinct e from unnest(audit_revert_source.entries) e)) then
    raise exception 'an entry is missing or not yours to revert' using errcode = 'P0002', hint = 'AUDIT_ENTRY_NOT_FOUND';
  end if;
  return found_entries;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revert_audit_entries (
  entries text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  entry jsonb;
  target regclass;
  v_old jsonb;
  v_new jsonb;
  current_row jsonb;
  columns text[];
  key_match text;
  affected integer;
  reverted integer := 0;
  v_correlation text := 'revert:' || gen_random_uuid()::text;
  v_previous text := current_setting('better_supabase.correlation_id', true);
  undo_entries jsonb := null;
begin
  perform set_config('better_supabase.correlation_id', v_correlation, true);
  for entry in select value from jsonb_array_elements("better_supabase"."audit_revert_source"(revert_audit_entries.entries)) loop
    target := (entry ->> 'table')::regclass;
    v_old := entry -> 'old';
    v_new := entry -> 'new';
    if target is null or entry ->> 'op' not in ('insert', 'update', 'delete') or jsonb_typeof(entry -> 'keys') <> 'array' then
      raise exception 'the entry is not a row change of a table that still exists' using errcode = '22023', hint = 'AUDIT_ENTRY_NOT_REVERTIBLE';
    end if;
    select string_agg(format('t.%I::text is not distinct from %L', k, coalesce(v_new, v_old) ->> k), ' and ')
    into key_match
    from jsonb_array_elements_text(entry -> 'keys') k;
    execute format('select to_jsonb(t) from %s t where %s', target, key_match) into current_row;
    case entry ->> 'op'
      when 'update' then
        select array_agg(k) into columns
        from jsonb_array_elements_text(coalesce(entry -> 'changed', (select jsonb_agg(n) from jsonb_object_keys(v_new) n))) k
        where v_new ? k and v_old ? k;
        if columns is null then
          raise exception 'the entry changed no column it can restore' using errcode = '22023', hint = 'AUDIT_ENTRY_NOT_REVERTIBLE';
        end if;
        if exists (select 1 from unnest(columns) k where v_old -> k = '"[redacted]"'::jsonb or v_new -> k = '"[redacted]"'::jsonb) then
          raise exception 'the entry holds redacted values' using errcode = '22023', hint = 'AUDIT_ENTRY_REDACTED';
        end if;
        if current_row is null or exists (
          select 1 from unnest(columns) k where current_row -> k is distinct from v_new -> k
        ) then
          raise exception 'the row changed after this entry' using errcode = 'P0001', hint = 'ROW_CHANGED_SINCE';
        end if;
        execute format(
          'update %s t set %s from jsonb_populate_record(null::%s, $1) o where %s',
          target,
          (select string_agg(format('%I = o.%I', k, k), ', ') from unnest(columns) k),
          target,
          key_match
        ) using v_old;
      when 'insert' then
        if current_row is null or exists (
          select 1 from jsonb_each(v_new) n
          where n.value <> '"[redacted]"'::jsonb and current_row -> n.key is distinct from n.value
        ) then
          raise exception 'the row changed after this entry' using errcode = 'P0001', hint = 'ROW_CHANGED_SINCE';
        end if;
        execute format('delete from %s t where %s', target, key_match);
      when 'delete' then
        if current_row is not null then
          raise exception 'a row with this key exists again' using errcode = 'P0001', hint = 'ROW_CHANGED_SINCE';
        end if;
        if exists (select 1 from jsonb_each(v_old) o where o.value = '"[redacted]"'::jsonb) then
          raise exception 'the entry holds redacted values' using errcode = '22023', hint = 'AUDIT_ENTRY_REDACTED';
        end if;
        select array_agg(att.attname::text order by att.attnum) into columns
        from pg_catalog.pg_attribute att
        where att.attrelid = target and att.attnum > 0 and not att.attisdropped
          and att.attgenerated = '' and v_old ? att.attname::text;
        execute format(
          'insert into %s (%s) overriding system value select %s from jsonb_populate_record(null::%s, $1) o',
          target,
          (select string_agg(format('%I', k), ', ') from unnest(columns) k),
          (select string_agg(format('o.%I', k), ', ') from unnest(columns) k),
          target
        ) using v_old;
    end case;
    get diagnostics affected = row_count;
    if affected <> 1 then
      raise exception 'not allowed to change this row' using errcode = '42501', hint = 'AUDIT_REVERT_FORBIDDEN';
    end if;
    reverted := reverted + 1;
  end loop;
  perform set_config('better_supabase.correlation_id', coalesce(v_previous, ''), true);
  undo_entries := "better_supabase"."audit_entries_correlated"(v_correlation);
  return jsonb_build_object('reverted', reverted, 'entries', undo_entries);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."audit_entries_correlated"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."audit_entries_correlated"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."audit_revert_source"(text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."audit_revert_source"(text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."revert_audit_entries"(text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."revert_audit_entries"(text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."audit_entries_correlated"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."audit_entries_correlated"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."audit_revert_source"(text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."audit_revert_source"(text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."revert_audit_entries"(text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."revert_audit_entries"(text[]) TO "authenticated", "service_role";
