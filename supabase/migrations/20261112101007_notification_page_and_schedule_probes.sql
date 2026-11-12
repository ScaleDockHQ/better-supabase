SET local check_function_bodies = off;

DROP FUNCTION "api"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean, timestamp WITH time zone, uuid, integer);

CREATE OR REPLACE FUNCTION api.notification_page (
  tenant        uuid                     DEFAULT NULL::uuid,
  status        text                     DEFAULT 'all'::text,
  types         text[]                   DEFAULT NULL::text[],
  subject_types text[]                   DEFAULT NULL::text[],
  search        text                     DEFAULT NULL::text,
  max_items     integer                  DEFAULT 50,
  skip          integer                  DEFAULT 0,
  read          boolean                  DEFAULT NULL::boolean,
  resolved      boolean                  DEFAULT NULL::boolean,
  dismissed     boolean                  DEFAULT false,
  before        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before_id     uuid                     DEFAULT NULL::uuid,
  total_cap     integer                  DEFAULT 10000,
  exclude_types text[]                   DEFAULT NULL::text[],
  subject_ids   text[]                   DEFAULT NULL::text[],
  any_of        jsonb                    DEFAULT NULL::jsonb,
  order_by      text                     DEFAULT 'newest'::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."notification_page"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17) $function$;

CREATE OR REPLACE FUNCTION api.outbox_has_work()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."outbox_has_work"() $function$;

CREATE OR REPLACE FUNCTION api.webhook_deliveries_has_work()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."webhook_deliveries_has_work"() $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_notifications (
  tenant        uuid                     DEFAULT NULL::uuid,
  status        text                     DEFAULT 'all'::text,
  types         text[]                   DEFAULT NULL::text[],
  before        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_items     integer                  DEFAULT 50,
  before_id     uuid                     DEFAULT NULL::uuid,
  subject_types text[]                   DEFAULT NULL::text[],
  search        text                     DEFAULT NULL::text,
  read          boolean                  DEFAULT NULL::boolean,
  resolved      boolean                  DEFAULT NULL::boolean,
  dismissed     boolean                  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_where text;
  result jsonb;
begin
  v_where := $q$rc."user_id" = $1$q$;
  if coalesce(list_notifications.status, 'all') = 'settled' then
    v_where := v_where || $q$ and (rc."resolved_at" is not null or rc."dismissed_at" is not null)$q$;
  elsif list_notifications.dismissed is not null then
    v_where := v_where || case when list_notifications.dismissed
      then $q$ and rc."dismissed_at" is not null$q$
      else $q$ and rc."dismissed_at" is null$q$ end;
  end if;
  if list_notifications.read is not null then
    v_where := v_where || case when list_notifications.read
      then $q$ and rc."read_at" is not null$q$
      else $q$ and rc."read_at" is null$q$ end;
  end if;
  if list_notifications.resolved is not null then
    v_where := v_where || case when list_notifications.resolved
      then $q$ and rc."resolved_at" is not null$q$
      else $q$ and rc."resolved_at" is null$q$ end;
  end if;
  if list_notifications.tenant is not null then
    v_where := v_where || $q$ and rc."tenant_id" = $2$q$;
  end if;
  if list_notifications.types is not null then
    v_where := v_where || $q$ and ev."type" = any($3)$q$;
  end if;
  if list_notifications.subject_types is not null then
    v_where := v_where || $q$ and ev."subject_type" = any($4)$q$;
  end if;
  if btrim(coalesce(list_notifications.search, '')) <> '' then
    v_where := v_where || $q$ and (concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike $5 or exists (select 1 from "better_supabase"."profiles" pr where pr."id" = ev."actor_id" and concat_ws(' ', pr."username", pr."full_name", pr."first_name", pr."last_name") ilike $5))$q$;
  end if;
  case coalesce(list_notifications.status, 'all')
    when 'unread' then v_where := v_where || $q$ and rc."read_at" is null$q$;
    when 'read' then v_where := v_where || $q$ and rc."read_at" is not null$q$;
    when 'unresolved' then v_where := v_where || $q$ and rc."resolved_at" is null$q$;
    else null;
  end case;
  if list_notifications.before is not null then
    v_where := v_where || $q$ and (rc."created_at", rc."id") < ($9, $10)$q$;
  end if;
  execute $q$select coalesce(jsonb_agg(x.item order by x.created_at desc, x.id desc), '[]')
  from (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."tenant_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where $q$ || v_where || $q$
    order by rc."created_at" desc, rc."id" desc
    limit $11
  ) x$q$
  into result
  using auth.uid(), list_notifications.tenant, list_notifications.types, list_notifications.subject_types,
    case when btrim(coalesce(list_notifications.search, '')) = '' then null else '%' || replace(replace(replace(btrim(list_notifications.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%' end, list_notifications.read, list_notifications.resolved, list_notifications.dismissed,
    list_notifications.before, coalesce(list_notifications.before_id, '00000000-0000-0000-0000-000000000000'::uuid),
    least(coalesce(list_notifications.max_items, 50), 500);
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_schedules (
  name_prefix text DEFAULT NULL::text,
  for_tenant  text DEFAULT NULL::text
)
  RETURNS TABLE (
    job_name        text,
    schedule        text,
    timezone        text,
    queue           text,
    tenant          text,
    next_run        timestamp with time zone,
    last_run        timestamp with time zone,
    lock_expires_at timestamp with time zone,
    created_at      timestamp with time zone,
    payload         jsonb,
    probe           text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_jobs regclass := pg_catalog.to_regclass('cron.job');
begin
  if v_jobs is null or list_schedules.for_tenant is not null then
    return;
  end if;
  return query execute format(
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz, null::jsonb, null::text
     from %s j where $1 is null or starts_with(j.jobname, $1) order by j.jobname', v_jobs)
    using name_prefix;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notification_page (
  tenant        uuid                     DEFAULT NULL::uuid,
  status        text                     DEFAULT 'all'::text,
  types         text[]                   DEFAULT NULL::text[],
  subject_types text[]                   DEFAULT NULL::text[],
  search        text                     DEFAULT NULL::text,
  max_items     integer                  DEFAULT 50,
  skip          integer                  DEFAULT 0,
  read          boolean                  DEFAULT NULL::boolean,
  resolved      boolean                  DEFAULT NULL::boolean,
  dismissed     boolean                  DEFAULT false,
  before        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before_id     uuid                     DEFAULT NULL::uuid,
  total_cap     integer                  DEFAULT 10000,
  exclude_types text[]                   DEFAULT NULL::text[],
  subject_ids   text[]                   DEFAULT NULL::text[],
  any_of        jsonb                    DEFAULT NULL::jsonb,
  order_by      text                     DEFAULT 'newest'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_where text;
  v_any text;
  v_limit integer := least(greatest(coalesce(notification_page.max_items, 50), 1), 500);
  v_order text;
  v_items jsonb;
  v_total bigint;
  v_args_cap integer := notification_page.total_cap;
begin
  v_order := case coalesce(notification_page.order_by, 'newest')
    when 'newest' then 'rc."created_at" desc, rc."id" desc'
    when 'oldest' then 'rc."created_at", rc."id"'
    when 'type' then 'ev."type" collate "C", rc."created_at" desc, rc."id" desc'
    when 'type_desc' then 'ev."type" collate "C" desc, rc."created_at" desc, rc."id" desc'
    when 'subject' then 'lower(coalesce(ev."subject_label", '''')) collate "C", rc."created_at" desc, rc."id" desc'
    when 'subject_desc' then 'lower(coalesce(ev."subject_label", '''')) collate "C" desc, rc."created_at" desc, rc."id" desc'
    when 'status' then 'case when rc."resolved_at" is not null then 2 when rc."read_at" is null then 0 else 1 end, rc."created_at" desc, rc."id" desc'
    when 'status_desc' then 'case when rc."resolved_at" is not null then 2 when rc."read_at" is null then 0 else 1 end desc, rc."created_at" desc, rc."id" desc'
  end;
  if v_order is null then
    raise exception 'order_by is one of newest, oldest, type, type_desc, subject, subject_desc, status, status_desc, not %', notification_page.order_by using errcode = '22023';
  end if;
  if notification_page.before is not null and coalesce(notification_page.order_by, 'newest') <> 'newest' then
    raise exception 'before pages the newest order; page another order with skip' using errcode = '22023';
  end if;
  v_where := $q$rc."user_id" = $1$q$;
  if coalesce(notification_page.status, 'all') = 'settled' then
    v_where := v_where || $q$ and (rc."resolved_at" is not null or rc."dismissed_at" is not null)$q$;
  elsif notification_page.dismissed is not null then
    v_where := v_where || case when notification_page.dismissed
      then $q$ and rc."dismissed_at" is not null$q$
      else $q$ and rc."dismissed_at" is null$q$ end;
  end if;
  if notification_page.read is not null then
    v_where := v_where || case when notification_page.read
      then $q$ and rc."read_at" is not null$q$
      else $q$ and rc."read_at" is null$q$ end;
  end if;
  if notification_page.resolved is not null then
    v_where := v_where || case when notification_page.resolved
      then $q$ and rc."resolved_at" is not null$q$
      else $q$ and rc."resolved_at" is null$q$ end;
  end if;
  if notification_page.tenant is not null then
    v_where := v_where || $q$ and rc."tenant_id" = $2$q$;
  end if;
  if notification_page.types is not null then
    v_where := v_where || $q$ and ev."type" = any($3)$q$;
  end if;
  if notification_page.subject_types is not null then
    v_where := v_where || $q$ and ev."subject_type" = any($4)$q$;
  end if;
  if btrim(coalesce(notification_page.search, '')) <> '' then
    v_where := v_where || $q$ and (concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike $5 or exists (select 1 from "better_supabase"."profiles" pr where pr."id" = ev."actor_id" and concat_ws(' ', pr."username", pr."full_name", pr."first_name", pr."last_name") ilike $5))$q$;
  end if;
  case coalesce(notification_page.status, 'all')
    when 'unread' then v_where := v_where || $q$ and rc."read_at" is null$q$;
    when 'read' then v_where := v_where || $q$ and rc."read_at" is not null$q$;
    when 'unresolved' then v_where := v_where || $q$ and rc."resolved_at" is null$q$;
    else null;
  end case;
  if notification_page.before is not null then
    v_where := v_where || $q$ and (rc."created_at", rc."id") < ($9, $10)$q$;
  end if;
  if notification_page.exclude_types is not null then
    v_where := v_where || $q$ and ev."type" <> all($11)$q$;
  end if;
  if notification_page.subject_ids is not null then
    v_where := v_where || $q$ and ev."subject_id" = any($12)$q$;
  end if;
  if notification_page.any_of is not null then
    if jsonb_typeof(notification_page.any_of) <> 'array'
      or exists (select 1 from jsonb_array_elements(notification_page.any_of) g where jsonb_typeof(g) <> 'object') then
      raise exception 'any_of is an array of filter objects' using errcode = '22023';
    end if;
    select coalesce(string_agg('(' || concat_ws(' and ', 'true', case when g ? 'types' then format('ev."type" = any(%L::text[])', array(select jsonb_array_elements_text(g -> 'types'))) end, case when g ? 'exclude_types' then format('ev."type" <> all(%L::text[])', array(select jsonb_array_elements_text(g -> 'exclude_types'))) end, case when g ? 'subject_types' then format('ev."subject_type" = any(%L::text[])', array(select jsonb_array_elements_text(g -> 'subject_types'))) end, case (g ->> 'read')::boolean when true then 'rc."read_at" is not null' when false then 'rc."read_at" is null' end, case (g ->> 'resolved')::boolean when true then 'rc."resolved_at" is not null' when false then 'rc."resolved_at" is null' end) || ')', ' or '), 'false')
    into v_any
    from jsonb_array_elements(notification_page.any_of) g;
    v_where := v_where || ' and (' || v_any || ')';
  end if;
  -- One row more than the page says whether another page exists, and the
  -- total stops counting at total_cap (null counts every row), so a large
  -- inbox never counts all of it. Pass before and before_id to page by key
  -- instead of skip.
  execute $q$select coalesce(jsonb_agg(p.item order by p.n), '[]')
  from (
    select row_number() over () as n, q.item
    from (
      select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."tenant_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item
      from "better_supabase"."notification_recipients" rc
      join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
      where $q$ || v_where || $q$
      order by $q$ || v_order || $q$
      offset $13
      limit $14 + 1
    ) q
  ) p$q$
  into v_items
  using auth.uid(), notification_page.tenant, notification_page.types, notification_page.subject_types,
    case when btrim(coalesce(notification_page.search, '')) = '' then null else '%' || replace(replace(replace(btrim(notification_page.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%' end, notification_page.read, notification_page.resolved, notification_page.dismissed,
    notification_page.before, coalesce(notification_page.before_id, '00000000-0000-0000-0000-000000000000'::uuid),
    notification_page.exclude_types, notification_page.subject_ids,
    greatest(coalesce(notification_page.skip, 0), 0), v_limit;
  execute $q$select count(*) from (
    select 1 from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where $q$ || v_where || case when v_args_cap is null then '' else format(' limit %s', greatest(v_args_cap, 1)) end || $q$
  ) c$q$
  into v_total
  using auth.uid(), notification_page.tenant, notification_page.types, notification_page.subject_types,
    case when btrim(coalesce(notification_page.search, '')) = '' then null else '%' || replace(replace(replace(btrim(notification_page.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%' end, notification_page.read, notification_page.resolved, notification_page.dismissed,
    notification_page.before, coalesce(notification_page.before_id, '00000000-0000-0000-0000-000000000000'::uuid),
    notification_page.exclude_types, notification_page.subject_ids;
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(x.value order by x.ordinality) from jsonb_array_elements(v_items) with ordinality x(value, ordinality) where x.ordinality <= v_limit), '[]'),
    'hasMore', jsonb_array_length(v_items) > v_limit,
    'limit', v_limit,
    'total', v_total,
    'totalCapped', v_args_cap is not null and v_total >= v_args_cap
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.outbox_has_work()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."outbox_consumers" c
    where (c."retry_at" is null or c."retry_at" <= now())
      and exists (select 1 from "better_supabase"."outbox_events" e where (e."xid", e."position") > (c."cursor_xid", c."cursor_position"))
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.schedule_has_work (
  probe text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_probe regprocedure := pg_catalog.to_regprocedure(probe || '()');
  v_work boolean;
begin
  if v_probe is null then
    return true;
  end if;
  execute format('select %s()', v_probe::oid::regproc) into v_work;
  return coalesce(v_work, true);
exception when others then
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.schedule_job (
  job_name text,
  schedule text,
  queue    text,
  payload  jsonb                    DEFAULT '{}'::jsonb,
  timezone text                     DEFAULT 'UTC'::text,
  next_run timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  tenant   text                     DEFAULT NULL::text,
  probe    text                     DEFAULT NULL::text
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  -- pg_cron is optional: its functions are looked up, not named, so
  -- plpgsql_check (supabase db lint) passes without the extension.
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
  v_id bigint;
begin
  if tenant is not null then
    raise exception 'pg_cron schedules have no tenant; set blocks.queue.options.scheduler to "drain" to keep one per schedule';
  end if;
  if v_schedule is null then
    raise exception 'schedule_job needs pg_cron: create extension pg_cron with schema pg_catalog, or set blocks.queue.options.scheduler to "drain"';
  end if;
  if timezone <> 'UTC' then
    raise exception 'pg_cron runs schedules in cron.timezone, not %; set blocks.queue.options.scheduler to "drain" for per-schedule time zones', timezone;
  end if;
  perform better_supabase.ensure_job_queue(queue);
  if probe is not null and not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = pg_catalog.to_regprocedure(probe || '()') and p.prorettype = 'boolean'::regtype
  ) then
    raise exception 'The probe % is not a function without arguments that returns boolean', probe using errcode = '22023';
  end if;
  execute format('select %s($1::text, $2::text, $3::text)', v_schedule::oid::regproc)
    into v_id
    using job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text)
      || case when probe is null then '' else format(' where better_supabase.schedule_has_work(%L)', probe) end;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unreported_usage (
  max_rows     integer DEFAULT 500,
  skip_meters  text[]  DEFAULT '{}'::text[],
  skip_tenants uuid[]  DEFAULT '{}'::uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with c as materialized (
    select * from "better_supabase"."usage_counters" c
    where c."value" > c."reported_value"
      and c."meter" <> all (coalesce(unreported_usage.skip_meters, '{}'))
      and c."tenant_id" <> all (coalesce(unreported_usage.skip_tenants, '{}'))
    order by c."day"
    limit max_rows
  ),
  tenants as materialized (
    select t.tenant, better_supabase.tenant_entitlements(t.tenant)::text[] as entitled, better_supabase.tenant_plans(t.tenant)::text[] as plans
    from (select distinct c."tenant_id" as tenant from c) t
  ),
  quota as materialized (
    select distinct on (p.tenant, p.meter) p.tenant, p.meter, q."limit" as quota_limit, q."period" as period
    from (select distinct c."tenant_id" as tenant, c."meter" as meter from c) p
    join tenants t on t.tenant = p.tenant
    join "better_supabase"."usage_quotas" q on q."meter" = p.meter
      and (q."tenant_id" = p.tenant or (q."tenant_id" is null and (q."plan" = '*' or q."plan" = any (t.entitled) or q."plan" = any (t.plans))))
    order by p.tenant, p.meter, (q."tenant_id" is not null) desc, q."limit" desc nulls first
  ),
  win as materialized (
    select d.tenant, d.period, d.day, "better_supabase"."usage_window_start"(d.tenant, d.period, d.day) as since
    from (
      select distinct c."tenant_id" as tenant, q.period, c."day" as day
      from c
      left join quota q on q.tenant = c."tenant_id" and q.meter = c."meter"
    ) d
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'organization_id', c."tenant_id",
    'meter', c."meter",
    'day', c."day",
    'value', c."value",
    'reported_value', c."reported_value",
    'included', q.quota_limit,
    'unlimited', q.period is not null and q.quota_limit is null,
    'window_before', (
      select coalesce(sum(o."value"), 0)
      from "better_supabase"."usage_counters" o
      where o."tenant_id" = c."tenant_id" and o."meter" = c."meter"
        and o."day" < c."day"
        and o."day" >= w.since
    )
  ) order by c."day", c."meter"), '[]'::jsonb)
  from c
  left join quota q on q.tenant = c."tenant_id" and q.meter = c."meter"
  join win w on w.tenant = c."tenant_id" and w.period is not distinct from q.period and w.day = c."day"
$function$;

CREATE OR REPLACE FUNCTION better_supabase.webhook_deliveries_has_work()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."webhook_deliveries" v
    where v."status" in ('pending', 'retrying', 'delivering')
      and v."available_at" <= now()
      and (v."lease_expires_at" is null or v."lease_expires_at" <= now())
  )
$function$;

REVOKE ALL
  ON FUNCTION "api"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean, timestamp
    WITH time zone, uuid, integer, text[], text[], jsonb, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean, timestamp
    WITH time zone, uuid, integer, text[], text[], jsonb, text)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."outbox_has_work"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."outbox_has_work"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."webhook_deliveries_has_work"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."webhook_deliveries_has_work"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_schedules"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_schedules"(text, text) TO "service_role";

REVOKE ALL
  ON FUNCTION "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean, timestamp
    WITH time zone, uuid, integer, text[], text[], jsonb, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean, timestamp
    WITH time zone, uuid, integer, text[], text[], jsonb, text)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."outbox_has_work"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."outbox_has_work"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."schedule_has_work"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."schedule_has_work"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."schedule_job"(text, text, text, jsonb, text, timestamp WITH time zone, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."schedule_job"(text, text, text, jsonb, text, timestamp WITH time zone, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."webhook_deliveries_has_work"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."webhook_deliveries_has_work"() TO "service_role";
