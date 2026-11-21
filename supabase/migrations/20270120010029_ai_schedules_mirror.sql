SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."ai_scheduled_tasks"
  DROP CONSTRAINT "ai_scheduled_tasks_external_id_check";

ALTER TABLE "better_supabase"."ai_scheduled_tasks"
  DROP CONSTRAINT "ai_scheduled_tasks_source_check";

CREATE OR REPLACE FUNCTION api.delete_mirrored_ai_task (
  tenant      uuid,
  source      text,
  external_id text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_mirrored_ai_task"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.mirror_ai_task (
  tenant      uuid,
  user_id     uuid,
  source      text,
  external_id text,
  fields      jsonb                    DEFAULT '{}'::jsonb,
  next_run_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mirror_ai_task"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.record_ai_task_run (
  tenant        uuid,
  source        text,
  external_id   text,
  scheduled_for timestamp with time zone,
  status        text,
  error         text                     DEFAULT NULL::text,
  chat_id       uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_ai_task_run"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_due_ai_tasks (
  batch integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_task "better_supabase"."ai_scheduled_tasks"%rowtype;
  v_run "better_supabase"."ai_task_runs"%rowtype;
  v_runs jsonb := '[]';
  v_unscheduled jsonb;
begin
  update "better_supabase"."ai_task_runs" y set "status" = 'failed', "error" = 'timed out', "finished_at" = now()
  where ((y."status" = 'running' and y."started_at" < now() - interval '30 minutes')
     or (y."status" = 'queued' and y."created_at" < now() - interval '30 minutes'))
    and exists (select 1 from "better_supabase"."ai_scheduled_tasks" x where x."id" = y."task_id" and x."source" = 'ai-schedules');
  for v_task in
    select * from "better_supabase"."ai_scheduled_tasks" x
    where x."enabled" and x."next_run_at" <= now() and x."source" = 'ai-schedules'
    order by x."next_run_at"
    limit least(greatest(claim_due_ai_tasks.batch, 1), 500)
    for update skip locked
  loop
    insert into "better_supabase"."ai_task_runs" ("task_id", "tenant_id", "user_id", "scheduled_at", "chat_id")
    values (v_task."id", v_task."tenant_id", v_task."user_id", v_task."next_run_at", v_task."chat_id")
    returning * into v_run;
    update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = null, "last_run_at" = now() where x."id" = v_task."id";
    perform "better_supabase"."enqueue_job"(queue => 'ai_task_run', payload => jsonb_build_object('run_id', v_run."id"), dedupe_key => 'ai-task:' || v_run."id"::text, dedupe_running => false);
    v_runs := v_runs || jsonb_build_array(jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at"));
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'cron', x."cron", 'timezone', x."timezone")), '[]')
  into v_unscheduled
  from "better_supabase"."ai_scheduled_tasks" x where x."enabled" and x."next_run_at" is null and x."source" = 'ai-schedules';
  return jsonb_build_object('runs', v_runs, 'unscheduled', v_unscheduled);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_mirrored_ai_task (
  tenant      uuid,
  source      text,
  external_id text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  delete from "better_supabase"."ai_scheduled_tasks" x
  where x."tenant_id" = delete_mirrored_ai_task.tenant and x."source" = delete_mirrored_ai_task.source
    and x."external_id" = delete_mirrored_ai_task.external_id and x."source" <> 'ai-schedules';
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_task (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'source', x."source", 'external_id', x."external_id", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
    select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
  ))
  from "better_supabase"."ai_scheduled_tasks" x where x."id" = get_ai_task.id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_tasks (
  tenant uuid,
  mine   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'source', x."source", 'external_id', x."external_id", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
    select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
  )) order by x."created_at" desc), '[]')
  from "better_supabase"."ai_scheduled_tasks" x
  where x."tenant_id" = list_ai_tasks.tenant and (not list_ai_tasks.mine or x."user_id" = auth.uid())
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mirror_ai_task (
  tenant      uuid,
  user_id     uuid,
  source      text,
  external_id text,
  fields      jsonb                    DEFAULT '{}'::jsonb,
  next_run_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_scheduled_tasks"%rowtype;
begin
  if mirror_ai_task.source is null or mirror_ai_task.source = 'ai-schedules' or length(mirror_ai_task.source) not between 1 and 64 then
    raise exception 'source must name another scheduler' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  if mirror_ai_task.external_id is null or length(mirror_ai_task.external_id) not between 1 and 200 then
    raise exception 'external_id is required' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  if jsonb_typeof(mirror_ai_task.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select * into v_row from "better_supabase"."ai_scheduled_tasks" x
  where x."tenant_id" = mirror_ai_task.tenant and x."source" = mirror_ai_task.source and x."external_id" = mirror_ai_task.external_id
  for update;
  if not found then
    insert into "better_supabase"."ai_scheduled_tasks" ("tenant_id", "user_id", "title", "prompt", "cron", "source", "external_id")
    values (mirror_ai_task.tenant, mirror_ai_task.user_id, mirror_ai_task.fields ->> 'title', mirror_ai_task.fields ->> 'prompt', mirror_ai_task.fields ->> 'cron', mirror_ai_task.source, mirror_ai_task.external_id)
    returning * into v_row;
  end if;
  update "better_supabase"."ai_scheduled_tasks" x set
    "title" = coalesce(mirror_ai_task.fields ->> 'title', x."title"),
    "prompt" = coalesce(mirror_ai_task.fields ->> 'prompt', x."prompt"),
    "cron" = coalesce(mirror_ai_task.fields ->> 'cron', x."cron"),
    "timezone" = coalesce(mirror_ai_task.fields ->> 'timezone', x."timezone"),
    "enabled" = coalesce((mirror_ai_task.fields ->> 'enabled')::boolean, x."enabled"),
    "next_run_at" = case when coalesce((mirror_ai_task.fields ->> 'enabled')::boolean, x."enabled") then mirror_ai_task.next_run_at else null end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'prompt', v_row."prompt", 'cron', v_row."cron", 'timezone', v_row."timezone", 'enabled', v_row."enabled", 'next_run_at', v_row."next_run_at", 'last_run_at', v_row."last_run_at", 'source', v_row."source", 'external_id', v_row."external_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_ai_tasks (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_ai_tasks.filters, '{}'::jsonb);
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
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('enabled') then
      raise exception 'facet is one of enabled' using errcode = '22023', hint = 'AI_TASK_INVALID';
    end if;
    with s as (
      select (case v_facet when 'enabled' then (x."enabled")::text end) as v
      from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
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
      select 1 from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'title', 'nextRunAt') then
    raise exception 'sort is one of createdAt, title, nextRunAt' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'source', x."source", 'external_id', x."external_id", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'source', x."source", 'external_id', x."external_id", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'source', x."source", 'external_id', x."external_id", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'source', x."source", 'external_id', x."external_id", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'source', x."source", 'external_id', x."external_id", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'source', x."source", 'external_id', x."external_id", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."title") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'nextRunAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'source', x."source", 'external_id', x."external_id", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((coalesce(x."next_run_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (coalesce(x."next_run_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."next_run_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'nextRunAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'source', x."source", 'external_id', x."external_id", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
      select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
    )) as j, jsonb_build_array((coalesce(x."next_run_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
        and (v_after is null or (coalesce(x."next_run_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."next_run_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."next_run_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."next_run_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."ai_scheduled_tasks" x
      where x."tenant_id" = page_ai_tasks.tenant
        and (coalesce(nullif(coalesce(v_filters #>> '{all,0}', v_filters ->> 'all'), '') = 'true', false) or x."user_id" = auth.uid())
        and (not (v_filters -> 'enabled' is not null and jsonb_typeof(v_filters -> 'enabled') <> 'null' and not (jsonb_typeof(v_filters -> 'enabled') = 'array' and jsonb_array_length(v_filters -> 'enabled') = 0)) or x."enabled"::text = any((case when jsonb_typeof(v_filters -> 'enabled') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'enabled')) else array[v_filters ->> 'enabled'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."prompt" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_ai_task_run (
  tenant        uuid,
  source        text,
  external_id   text,
  scheduled_for timestamp with time zone,
  status        text,
  error         text                     DEFAULT NULL::text,
  chat_id       uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_task "better_supabase"."ai_scheduled_tasks"%rowtype;
  v_run "better_supabase"."ai_task_runs"%rowtype;
begin
  if record_ai_task_run.status not in ('queued', 'running', 'completed', 'failed') then
    raise exception '% is not a run status', record_ai_task_run.status using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  select * into v_task from "better_supabase"."ai_scheduled_tasks" x
  where x."tenant_id" = record_ai_task_run.tenant and x."source" = record_ai_task_run.source
    and x."external_id" = record_ai_task_run.external_id and x."source" <> 'ai-schedules'
  for update;
  if not found then
    return null;
  end if;
  select * into v_run from "better_supabase"."ai_task_runs" y where y."task_id" = v_task."id" and y."scheduled_at" = record_ai_task_run.scheduled_for for update;
  if not found then
    insert into "better_supabase"."ai_task_runs" ("task_id", "tenant_id", "user_id", "scheduled_at", "status")
    values (v_task."id", v_task."tenant_id", v_task."user_id", record_ai_task_run.scheduled_for, record_ai_task_run.status)
    returning * into v_run;
  end if;
  update "better_supabase"."ai_task_runs" y set "status" = record_ai_task_run.status, "started_at" = case when record_ai_task_run.status = 'queued' then y."started_at" else coalesce(y."started_at", now()) end, "error" = left(record_ai_task_run.error, 4000), "chat_id" = coalesce(record_ai_task_run.chat_id, y."chat_id"), "finished_at" = case when record_ai_task_run.status in ('completed', 'failed') then now() else y."finished_at" end
  where y."id" = v_run."id"
  returning * into v_run;
  update "better_supabase"."ai_scheduled_tasks" x set "last_run_at" = greatest(coalesce(x."last_run_at", record_ai_task_run.scheduled_for), record_ai_task_run.scheduled_for) where x."id" = v_task."id";
  return jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_task (
  tenant      uuid,
  id          uuid                     DEFAULT NULL::uuid,
  fields      jsonb                    DEFAULT '{}'::jsonb,
  next_run_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_ai_task.id;
  v_row "better_supabase"."ai_scheduled_tasks"%rowtype;
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_chat uuid;
  v_agent uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(save_ai_task.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  if save_ai_task.fields ? 'timezone' then
    begin
      perform now() at time zone (save_ai_task.fields ->> 'timezone');
    exception when others then
      raise exception '% is not a time zone', save_ai_task.fields ->> 'timezone' using errcode = '22023', hint = 'AI_TASK_INVALID';
    end;
  end if;
  if v_id is null then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_task.tenant, 'ai_schedules.write'), false)) or auth.uid() is null then
      raise exception 'you may not schedule tasks here' using errcode = '42501', hint = 'AI_TASK_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_scheduled_tasks" ("tenant_id", "user_id", "title", "prompt", "cron")
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id and x."tenant_id" = save_ai_task.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ai_schedules.manage'), false)) then
      raise exception 'task % not found', v_id using errcode = 'P0002', hint = 'AI_TASK_NOT_FOUND';
    end if;
  end if;
  v_chat := (save_ai_task.fields ->> 'chat_id')::uuid;
  if v_chat is not null and not v_service and not exists (select 1 from "better_supabase"."ai_chats" c where c."id" = v_chat and c."owner_id" = v_row."user_id" and c."tenant_id" = v_row."tenant_id")
  then
    raise exception 'chat % is not a chat of this task''s user', v_chat using errcode = '42501', hint = 'AI_TASK_CHAT_FORBIDDEN';
  end if;
  v_agent := (save_ai_task.fields ->> 'agent_id')::uuid;
  if v_agent is not null and not v_service and not exists (select 1 from "better_supabase"."agents" g where g."id" = v_agent and g."tenant_id" = v_row."tenant_id" and (g."owner_id" = v_row."user_id" or g."published_at" is not null))
  then
    raise exception 'agent % is not an agent this task''s user may use', v_agent using errcode = '42501', hint = 'AI_TASK_AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_scheduled_tasks" x set
    "title" = coalesce(save_ai_task.fields ->> 'title', x."title"),
    "prompt" = coalesce(save_ai_task.fields ->> 'prompt', x."prompt"),
    "cron" = coalesce(save_ai_task.fields ->> 'cron', x."cron"),
    "timezone" = coalesce(save_ai_task.fields ->> 'timezone', x."timezone"),
    "chat_id" = case when save_ai_task.fields ? 'chat_id' then (save_ai_task.fields ->> 'chat_id')::uuid else x."chat_id" end,
    "agent_id" = case when save_ai_task.fields ? 'agent_id' then (save_ai_task.fields ->> 'agent_id')::uuid else x."agent_id" end,
    "enabled" = coalesce((save_ai_task.fields ->> 'enabled')::boolean, x."enabled"),
    "next_run_at" = case
      when (save_ai_task.fields ->> 'enabled')::boolean is false then null
      when v_service and (save_ai_task.next_run_at is not null or save_ai_task.fields ? 'cron' or save_ai_task.fields ? 'timezone') then save_ai_task.next_run_at
      when save_ai_task.id is null or save_ai_task.fields ? 'cron' or save_ai_task.fields ? 'timezone' then null
      else x."next_run_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'prompt', v_row."prompt", 'cron', v_row."cron", 'timezone', v_row."timezone", 'enabled', v_row."enabled", 'next_run_at', v_row."next_run_at", 'last_run_at', v_row."last_run_at", 'source', v_row."source", 'external_id', v_row."external_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.schedule_ai_tasks (
  items jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_items jsonb := case when jsonb_typeof(schedule_ai_tasks.items) = 'object' then schedule_ai_tasks.items -> 'items' else schedule_ai_tasks.items end;
  v_count integer;
begin
  update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = (item ->> 'next_run_at')::timestamptz
  from jsonb_array_elements(case when jsonb_typeof(v_items) = 'array' then v_items else '[]' end) item
  where x."id" = (item ->> 'id')::uuid and x."enabled" and x."next_run_at" is null and x."source" = 'ai-schedules';
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_ai_task_run (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."ai_task_runs"%rowtype;
  v_task "better_supabase"."ai_scheduled_tasks"%rowtype;
begin
  update "better_supabase"."ai_task_runs" y set "status" = 'running', "started_at" = now()
  where y."id" = start_ai_task_run.id and y."status" = 'queued'
  returning * into v_run;
  if not found then
    return null;
  end if;
  select * into v_task from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_run."task_id";
  return jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at") || jsonb_build_object('task', jsonb_build_object('id', v_task."id", 'tenant_id', v_task."tenant_id", 'user_id', v_task."user_id", 'chat_id', v_task."chat_id", 'agent_id', v_task."agent_id", 'title', v_task."title", 'prompt', v_task."prompt", 'cron', v_task."cron", 'timezone', v_task."timezone", 'enabled', v_task."enabled", 'next_run_at', v_task."next_run_at", 'last_run_at', v_task."last_run_at", 'source', v_task."source", 'external_id', v_task."external_id", 'created_at', v_task."created_at", 'updated_at', v_task."updated_at"));
end;
$function$;

ALTER TABLE "better_supabase"."ai_scheduled_tasks"
  ADD CONSTRAINT "bsb_ai_scheduled_tasks_external_id_check" CHECK (((length(external_id) >= 1) AND (length(external_id) <= 200)));

ALTER TABLE "better_supabase"."ai_scheduled_tasks"
  ADD CONSTRAINT "bsb_ai_scheduled_tasks_source_check" CHECK (((length(source) >= 1) AND (length(source) <= 64)));

CREATE UNIQUE INDEX ai_scheduled_tasks_external_idx ON better_supabase.ai_scheduled_tasks USING btree (tenant_id, source, external_id)
  WHERE (external_id IS NOT NULL);

REVOKE ALL ON FUNCTION "api"."delete_mirrored_ai_task"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_mirrored_ai_task"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."mirror_ai_task"(uuid, uuid, text, text, jsonb, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mirror_ai_task"(uuid, uuid, text, text, jsonb, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_ai_task_run"(uuid, text, text, timestamp WITH time zone, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_ai_task_run"(uuid, text, text, timestamp WITH time zone, text, text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_mirrored_ai_task"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_mirrored_ai_task"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mirror_ai_task"(uuid, uuid, text, text, jsonb, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mirror_ai_task"(uuid, uuid, text, text, jsonb, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_ai_task_run"(uuid, text, text, timestamp WITH time zone, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_ai_task_run"(uuid, text, text, timestamp WITH time zone, text, text, uuid) TO "service_role";
