SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."collection_star_folders"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."iteration_cadences"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."iteration_snapshots"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."milestones"
  ENABLE ROW LEVEL SECURITY;

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
  v_where := $q$rc."user_id" = $1 and (rc."snoozed_until" <= now() or rc."snoozed_until" is null)$q$;
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

CREATE OR REPLACE FUNCTION better_supabase.notification_counts (
  tenant     uuid    DEFAULT NULL::uuid,
  actionable text[]  DEFAULT NULL::text[],
  cap        integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'unread', (
      select count(*) from (
        select 1 from "better_supabase"."notification_recipients" rc
        where rc."user_id" = auth.uid()
          and rc."read_at" is null
          and rc."dismissed_at" is null
          and (rc."snoozed_until" <= now() or rc."snoozed_until" is null)
          and (notification_counts.tenant is null or rc."tenant_id" = notification_counts.tenant)
        limit notification_counts.cap
      ) u
    ),
    'actionable', coalesce(act.rows, 0),
    'actionable_subjects', coalesce(act.subjects, 0)
  )
  from (select 1) one
  left join lateral (
    select count(*) as rows, count(distinct a.subject_key) as subjects
    from (
      select case when ev."subject_type" is not null and ev."subject_id" is not null then jsonb_build_array(ev."tenant_id", ev."subject_type", ev."subject_id")::text else rc."id"::text end as subject_key
      from "better_supabase"."notification_recipients" rc
      join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
      where cardinality(coalesce(notification_counts.actionable, '{}')) > 0
        and rc."user_id" = auth.uid()
        and rc."dismissed_at" is null
        and rc."resolved_at" is null and ev."type" = any(coalesce(notification_counts.actionable, '{}'))
        and (notification_counts.tenant is null or rc."tenant_id" = notification_counts.tenant)
      limit notification_counts.cap
    ) a
  ) act on true
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
  v_where := $q$rc."user_id" = $1 and (rc."snoozed_until" <= now() or rc."snoozed_until" is null)$q$;
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
