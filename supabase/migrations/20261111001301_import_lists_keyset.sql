SET local check_function_bodies = off;

DROP INDEX "better_supabase"."import_run_issues_run_idx";

DROP FUNCTION "api"."list_import_diff"(uuid, text, integer, integer);

DROP FUNCTION "api"."list_import_issues"(uuid, text, integer, integer);

DROP FUNCTION "better_supabase"."list_import_diff"(uuid, text, integer, integer);

DROP FUNCTION "better_supabase"."list_import_issues"(uuid, text, integer, integer);

CREATE OR REPLACE FUNCTION api.list_import_diff (
  run        uuid,
  entity     text    DEFAULT NULL::text,
  row_limit  integer DEFAULT 50,
  row_offset integer DEFAULT 0,
  after      text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_import_diff"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_import_issues (
  run        uuid,
  entity     text    DEFAULT NULL::text,
  row_limit  integer DEFAULT 50,
  row_offset integer DEFAULT 0,
  after      text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_import_issues"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_import_diff (
  run        uuid,
  entity     text    DEFAULT NULL::text,
  row_limit  integer DEFAULT 50,
  row_offset integer DEFAULT 0,
  after      text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_counts jsonb;
  v_diff jsonb;
  v_limit integer := least(greatest(coalesce(list_import_diff.row_limit, 50), 1), 200);
  v_after integer := 0;
  v_rows jsonb;
  v_found integer;
  v_next text;
begin
  select r."counts", r."diff" into v_counts, v_diff from "better_supabase"."import_runs" r where r."id" = list_import_diff.run;
  if v_counts is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if list_import_diff.after is not null then
    if list_import_diff.after !~ '^[0-9]{1,9}$' then
      raise exception 'after is not a cursor of this list' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    v_after := list_import_diff.after::integer;
  end if;
  select coalesce(jsonb_agg(d.value order by d.ord) filter (where d.n <= v_limit), '[]'::jsonb),
    count(*),
    max(d.ord::text) filter (where d.n = v_limit)
  into v_rows, v_found, v_next
  from (
    select p.value, p.ord, row_number() over (order by p.ord) as n
    from (
      select e.value, e.ord
      from jsonb_array_elements(coalesce(v_diff, '[]'::jsonb)) with ordinality e(value, ord)
      where e.ord > v_after
        and (list_import_diff.entity is null or e.value ->> 'entity' = list_import_diff.entity)
      order by e.ord
      offset case when list_import_diff.after is null then greatest(coalesce(list_import_diff.row_offset, 0), 0) else 0 end
      limit v_limit + 1
    ) p
  ) d;
  return jsonb_build_object(
    'counts', case when list_import_diff.entity is null then v_counts else coalesce(v_counts -> list_import_diff.entity, '{}'::jsonb) end,
    'rows', v_rows,
    'next_cursor', case when v_found > v_limit then v_next else null end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_import_issues (
  run        uuid,
  entity     text    DEFAULT NULL::text,
  row_limit  integer DEFAULT 50,
  row_offset integer DEFAULT 0,
  after      text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_limit integer := least(greatest(coalesce(list_import_issues.row_limit, 50), 1), 200);
  v_after_at timestamptz;
  v_after_id uuid;
  v_total integer;
  v_rows jsonb;
  v_next text;
  v_found integer;
begin
  select r."tenant_id" into v_tenant from "better_supabase"."import_runs" r where r."id" = list_import_issues.run;
  if v_tenant is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list import issues' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if list_import_issues.after is not null then
    begin
      v_after_at := split_part(convert_from(decode(translate(list_import_issues.after, '-_.', '+/='), 'base64'), 'utf8'), '|', 1)::timestamptz;
      v_after_id := split_part(convert_from(decode(translate(list_import_issues.after, '-_.', '+/='), 'base64'), 'utf8'), '|', 2)::uuid;
    exception when others then
      raise exception 'after is not a cursor of this list' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end;
  else
    select count(*) into v_total from (
      select 1 from "better_supabase".import_run_issues i
      where i."run_id" = list_import_issues.run
        and (list_import_issues.entity is null or i."entity" = list_import_issues.entity)
      limit 10001
    ) c;
  end if;
  select coalesce(jsonb_agg(to_jsonb(t) - 'id' - 'n' order by t."created_at", t."id") filter (where t."n" <= v_limit), '[]'::jsonb),
    count(*),
    max(translate(encode(convert_to(t."created_at"::text || '|' || t."id"::text, 'utf8'), 'base64'), '+/=', '-_.')) filter (where t."n" = v_limit)
  into v_rows, v_found, v_next
  from (
    select p.*, row_number() over (order by p."created_at", p."id") as "n"
    from (
      select i."id", i."entity", i."key", i."kind", i."code", i."message", i."created_at", i."resolved_at"
      from "better_supabase".import_run_issues i
      where i."run_id" = list_import_issues.run
        and (list_import_issues.entity is null or i."entity" = list_import_issues.entity)
        and (v_after_at is null or (i."created_at", i."id") > (v_after_at, v_after_id))
      order by i."created_at", i."id"
      limit v_limit + 1
      offset case when list_import_issues.after is null then greatest(coalesce(list_import_issues.row_offset, 0), 0) else 0 end
    ) p
  ) t;
  return jsonb_build_object(
    'rows', v_rows,
    'total', case when v_total is null then null else least(v_total, 10000) end,
    'capped', coalesce(v_total > 10000, false),
    'next_cursor', case when v_found > v_limit then v_next else null end
  );
end;
$function$;

CREATE INDEX import_run_issues_page_idx ON better_supabase.import_run_issues USING btree (run_id, created_at, id);

CREATE INDEX import_run_issues_run_idx ON better_supabase.import_run_issues USING btree (run_id, entity, created_at, id);

REVOKE ALL ON FUNCTION "api"."list_import_diff"(uuid, text, integer, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_import_diff"(uuid, text, integer, integer, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_import_issues"(uuid, text, integer, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_import_issues"(uuid, text, integer, integer, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_import_diff"(uuid, text, integer, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_import_diff"(uuid, text, integer, integer, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_import_issues"(uuid, text, integer, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_import_issues"(uuid, text, integer, integer, text) TO "authenticated", "service_role";
