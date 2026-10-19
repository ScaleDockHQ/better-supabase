SET local check_function_bodies = off;

DROP FUNCTION "api"."list_activity"(uuid, text, text, timestamp WITH time zone, integer);

DROP FUNCTION "better_supabase"."list_activity"(uuid, text, text, timestamp WITH time zone, integer);

CREATE OR REPLACE FUNCTION api.list_activity (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50,
  sources      text[]                   DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_activity"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION better_supabase.activity_subject_deliveries (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  before       timestamp with time zone,
  max_rows     integer
)
  RETURNS TABLE (
    entry jsonb,
    at    timestamp with time zone,
    id    text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query
  select jsonb_build_object('id', d."id"::text, 'organization_id', ev."organization_id", 'event_id', null::text, 'type', 'delivery.' || d."status", 'actor_id', null::uuid, 'subject_type', activity_subject_deliveries.subject_type, 'subject_id', activity_subject_deliveries.subject_id, 'summary', ev."summary", 'data', jsonb_strip_nulls(jsonb_build_object('notificationId', ev."id", 'notificationType', ev."type", 'channel', d."channel", 'status', d."status", 'userId', rc."user_id", 'providerStatus', d."provider_status", 'templateKey', d."template_key", 'error', d."error", 'deliveredAt', d."delivered_at")), 'occurred_at', d."created_at", 'source', 'delivery'),
    d."created_at", d."id"::text
  from "better_supabase"."notification_deliveries" d
  join "better_supabase"."notification_recipients" rc on rc."id" = d."recipient_id"
  join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
  where activity_subject_deliveries.subject_type = any ('{customer,company,person,deal,work_item,employee,product,product_variant,drive_node,application,project,task}'::text[])
    and ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
      or (coalesce(better_supabase.can('tenant', activity_subject_deliveries.tenant, 'activity.read'), false) and coalesce(better_supabase.can('tenant', activity_subject_deliveries.tenant, 'notifications.send'), false)))
    and ev."organization_id" = activity_subject_deliveries.tenant
    and ev."subject_type" = activity_subject_deliveries.subject_type
    and ev."subject_id" = activity_subject_deliveries.subject_id
    and (activity_subject_deliveries.before is null or d."created_at" < activity_subject_deliveries.before)
  order by d."created_at" desc, d."id" desc
  limit least(greatest(coalesce(activity_subject_deliveries.max_rows, 50), 1), 500);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_activity (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50,
  sources      text[]                   DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
  v_table text;
begin
  if list_activity.subject_id is not null and list_activity.subject_type = any ('{customer,company,person,deal,work_item,employee,product,product_variant,drive_node,application,project,task}'::text[])
    and not "better_supabase"."activity_subject_readable"(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;
  end if;
  if list_activity.subject_id is not null then
    v_table := case list_activity.subject_type
      when 'customer' then 'public.customers'
      when 'company' then 'better_supabase.companies'
      when 'person' then 'better_supabase.people'
      when 'deal' then 'better_supabase.deals'
      when 'work_item' then 'better_supabase.work_items'
      when 'employee' then 'better_supabase.employees'
      when 'product' then 'better_supabase.products'
      when 'product_variant' then 'better_supabase.product_variants'
      when 'drive_node' then 'better_supabase.drive_nodes'
      when 'application' then 'better_supabase.applications'
      when 'project' then 'public.projects'
      when 'task' then 'public.tasks'
    end;
  end if;
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', l."id"::text, 'organization_id', l."organization_id", 'event_id', null::text, 'type', coalesce(l."event_type", 'audit.' || l."op"), 'actor_id', l."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', l."summary", 'data', jsonb_strip_nulls(jsonb_build_object('op', l."op", 'changed', to_jsonb(l."changed"), 'table', l."table_name")), 'occurred_at', l."occurred_at", 'source', 'audit') as entry,
      l."occurred_at" as at, l."id"::text as id
    from "better_supabase"."audit_events" l
    where v_table is not null
      and (list_activity.sources is null or 'audit' = any (list_activity.sources))
      and l."table_name" = v_table
      and l."record_id" = list_activity.subject_id
      and l."organization_id" = list_activity.tenant
      and (list_activity.before is null or l."occurred_at" < list_activity.before)
    order by l."occurred_at" desc, l."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', r."id"::text, 'organization_id', r."tenant_id", 'event_id', null::text, 'type', 'run.' || r."status", 'actor_id', r."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', null::text, 'data', jsonb_strip_nulls(jsonb_build_object('runId', r."id", 'definition', r."definition", 'engine', r."engine", 'status', r."status", 'mode', r."mode", 'error', r."error"::text, 'completedAt', r."completed_at")), 'occurred_at', r."created_at", 'source', 'run') as entry,
      r."created_at" as at, r."id"::text as id
    from "better_supabase"."workflow_runs" r
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{customer,company,person,deal,work_item,employee,product,product_variant,drive_node,application,project,task}'::text[])
      and (list_activity.sources is null or 'run' = any (list_activity.sources))
      and r."tenant_id" = list_activity.tenant
      and r."subject_type" = list_activity.subject_type
      and r."subject_id" = list_activity.subject_id
      and (list_activity.before is null or r."created_at" < list_activity.before)
    order by r."created_at" desc, r."id" desc
    limit v_limit)
    union all
    (select d.entry, d.at, d.id
    from "better_supabase"."activity_subject_deliveries"(list_activity.tenant, list_activity.subject_type, list_activity.subject_id, list_activity.before, v_limit) d
    where list_activity.subject_id is not null
      and (list_activity.sources is null or 'delivery' = any (list_activity.sources)))
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."list_activity"(uuid, text, text, timestamp WITH time zone, integer, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_activity"(uuid, text, text, timestamp WITH time zone, integer, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."activity_subject_deliveries"(uuid, text, text, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."activity_subject_deliveries"(uuid, text, text, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_activity"(uuid, text, text, timestamp WITH time zone, integer, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_activity"(uuid, text, text, timestamp WITH time zone, integer, text[]) TO "authenticated", "service_role";
