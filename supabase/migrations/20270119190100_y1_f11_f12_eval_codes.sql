SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.page_eval_datasets (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_eval_datasets.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'id') = 'array' then v_filters -> 'id' when jsonb_typeof(v_filters -> 'id') in ('string', 'number') then jsonb_build_array(v_filters -> 'id') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'id is a uuid' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt', 'lastRunAt') then
    raise exception 'sort is one of name, createdAt, lastRunAt' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastRunAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'lastRunAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"),
      'last_run_at', (select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id")
    ) as j, jsonb_build_array((coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
        and (v_after is null or (coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce((select max(y."created_at") from "better_supabase"."eval_runs" y where y."dataset_id" = x."id"), 'epoch'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."eval_datasets" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_datasets.tenant::text, '')
        and (not (v_filters -> 'id' is not null and jsonb_typeof(v_filters -> 'id') <> 'null' and not (jsonb_typeof(v_filters -> 'id') = 'array' and jsonb_array_length(v_filters -> 'id') = 0)) or x."id" = any((case when jsonb_typeof(v_filters -> 'id') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'id')) else array[v_filters ->> 'id'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_eval_runs (
  tenant  uuid  DEFAULT NULL::uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_eval_runs.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then v_filters -> 'datasetId' when jsonb_typeof(v_filters -> 'datasetId') in ('string', 'number') then jsonb_build_array(v_filters -> 'datasetId') else '[]'::jsonb end) s where s !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') then
    raise exception 'datasetId is a uuid' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'model', 'promptName') then
      raise exception 'facet is one of status, model, promptName' using errcode = '22023', hint = 'AI_EVAL_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'model' then (x."model")::text when 'promptName' then (x."prompt_name")::text end) as v
      from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'finishedAt') then
    raise exception 'sort is one of createdAt, finishedAt' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'dataset_id', x."dataset_id", 'tenant_id', x."tenant_id", 'prompt_name', x."prompt_name", 'prompt_version', x."prompt_version", 'model', x."model", 'scorers', x."scorers", 'status', x."status", 'summary', x."summary", 'created_at', x."created_at", 'finished_at', x."finished_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'dataset_id', x."dataset_id", 'tenant_id', x."tenant_id", 'prompt_name', x."prompt_name", 'prompt_version', x."prompt_version", 'model', x."model", 'scorers', x."scorers", 'status', x."status", 'summary', x."summary", 'created_at', x."created_at", 'finished_at', x."finished_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'dataset_id', x."dataset_id", 'tenant_id', x."tenant_id", 'prompt_name', x."prompt_name", 'prompt_version', x."prompt_version", 'model', x."model", 'scorers', x."scorers", 'status', x."status", 'summary', x."summary", 'created_at', x."created_at", 'finished_at', x."finished_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'dataset_id', x."dataset_id", 'tenant_id', x."tenant_id", 'prompt_name', x."prompt_name", 'prompt_version', x."prompt_version", 'model', x."model", 'scorers', x."scorers", 'status', x."status", 'summary', x."summary", 'created_at', x."created_at", 'finished_at', x."finished_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'finishedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'dataset_id', x."dataset_id", 'tenant_id', x."tenant_id", 'prompt_name', x."prompt_name", 'prompt_version', x."prompt_version", 'model', x."model", 'scorers', x."scorers", 'status', x."status", 'summary', x."summary", 'created_at', x."created_at", 'finished_at', x."finished_at") as j, jsonb_build_array((coalesce(x."finished_at", 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
        and (v_after is null or (coalesce(x."finished_at", 'epoch'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."finished_at", 'epoch'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."finished_at", 'epoch'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."finished_at", 'epoch'::timestamptz) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'finishedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_EVAL_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'dataset_id', x."dataset_id", 'tenant_id', x."tenant_id", 'prompt_name', x."prompt_name", 'prompt_version', x."prompt_version", 'model', x."model", 'scorers', x."scorers", 'status', x."status", 'summary', x."summary", 'created_at', x."created_at", 'finished_at', x."finished_at") as j, jsonb_build_array((coalesce(x."finished_at", 'epoch'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
        and (v_after is null or (coalesce(x."finished_at", 'epoch'::timestamptz), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."finished_at", 'epoch'::timestamptz) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."eval_runs" x
      where coalesce(x."tenant_id"::text, '') = coalesce(page_eval_runs.tenant::text, '')
        and (not (v_filters -> 'datasetId' is not null and jsonb_typeof(v_filters -> 'datasetId') <> 'null' and not (jsonb_typeof(v_filters -> 'datasetId') = 'array' and jsonb_array_length(v_filters -> 'datasetId') = 0)) or x."dataset_id" = any((case when jsonb_typeof(v_filters -> 'datasetId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'datasetId')) else array[v_filters ->> 'datasetId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'model' is not null and jsonb_typeof(v_filters -> 'model') <> 'null' and not (jsonb_typeof(v_filters -> 'model') = 'array' and jsonb_array_length(v_filters -> 'model') = 0)) or x."model" = any((case when jsonb_typeof(v_filters -> 'model') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'model')) else array[v_filters ->> 'model'] end)::text[]))
        and (not (v_filters -> 'promptName' is not null and jsonb_typeof(v_filters -> 'promptName') <> 'null' and not (jsonb_typeof(v_filters -> 'promptName') = 'array' and jsonb_array_length(v_filters -> 'promptName') = 0)) or x."prompt_name" = any((case when jsonb_typeof(v_filters -> 'promptName') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'promptName')) else array[v_filters ->> 'promptName'] end)::text[]))
        and (v_search is null or x."prompt_name" ilike v_search or x."model" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;
