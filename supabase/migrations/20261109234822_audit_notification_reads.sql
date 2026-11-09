SET local check_function_bodies = off;

DROP INDEX "better_supabase"."audit_events_organization_idx";

DROP FUNCTION "api"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp WITH time zone);

DROP FUNCTION "api"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
  WITH time zone, timestamp WITH time zone, text, integer, boolean, integer);

DROP FUNCTION "api"."notification_counts"(uuid, text[]);

DROP FUNCTION "api"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean);

DROP FUNCTION "better_supabase"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
  WITH time zone);

DROP FUNCTION "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
  WITH time zone, timestamp WITH time zone, text, integer, boolean, integer);

DROP FUNCTION "better_supabase"."list_notifications"(uuid, text, text[], timestamp WITH time zone, integer, uuid, text[], text, boolean, boolean, boolean);

DROP FUNCTION "better_supabase"."notification_counts"(uuid, text[]);

DROP FUNCTION "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean);

CREATE OR REPLACE FUNCTION api.audit_event_types (
  for_tenants uuid[] DEFAULT NULL::uuid[]
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."audit_event_types"($1) $function$;

CREATE OR REPLACE FUNCTION api.count_audit_events (
  for_tenants         uuid[]                   DEFAULT NULL::uuid[],
  for_event_types     text[]                   DEFAULT NULL::text[],
  for_actors          uuid[]                   DEFAULT NULL::uuid[],
  for_target_types    text[]                   DEFAULT NULL::text[],
  for_records         text[]                   DEFAULT NULL::text[],
  for_categories      text[]                   DEFAULT NULL::text[],
  for_outcomes        text[]                   DEFAULT NULL::text[],
  search              text                     DEFAULT NULL::text,
  for_sources         text[]                   DEFAULT NULL::text[],
  for_actor_kinds     text[]                   DEFAULT NULL::text[],
  for_correlation_ids text[]                   DEFAULT NULL::text[],
  since               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  cap                 integer                  DEFAULT NULL::integer
)
  RETURNS bigint
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."count_audit_events"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) $function$;

CREATE OR REPLACE FUNCTION api.get_audit_event (
  entry_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_audit_event"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_audit_events (
  for_tenants         uuid[]                   DEFAULT NULL::uuid[],
  for_event_types     text[]                   DEFAULT NULL::text[],
  for_actors          uuid[]                   DEFAULT NULL::uuid[],
  for_target_types    text[]                   DEFAULT NULL::text[],
  for_records         text[]                   DEFAULT NULL::text[],
  for_categories      text[]                   DEFAULT NULL::text[],
  for_outcomes        text[]                   DEFAULT NULL::text[],
  search              text                     DEFAULT NULL::text,
  for_sources         text[]                   DEFAULT NULL::text[],
  for_actor_kinds     text[]                   DEFAULT NULL::text[],
  for_correlation_ids text[]                   DEFAULT NULL::text[],
  since               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  cursor_at           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  cursor_id           text                     DEFAULT NULL::text,
  max_items           integer                  DEFAULT 50,
  ascending           boolean                  DEFAULT false,
  skip                integer                  DEFAULT 0,
  entry_fields        text                     DEFAULT 'full'::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_audit_events"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19) $function$;

CREATE OR REPLACE FUNCTION api.notification_counts (
  tenant     uuid    DEFAULT NULL::uuid,
  actionable text[]  DEFAULT NULL::text[],
  cap        integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."notification_counts"($1, $2, $3) $function$;

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
  total_cap     integer                  DEFAULT 10000
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."notification_page"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13) $function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event_types (
  for_tenants uuid[] DEFAULT NULL::uuid[]
)
  RETURNS text[]
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_types text[] := '{}';
  v_next text;
begin
  -- One loose index scan per tenant: min() over the (tenant, event type) index
  -- reads one entry, where "tenant = any(...)" would read every row. Without
  -- for_tenants the scan has no tenant to lead with, so pass the tenants.
  loop
    if cardinality(for_tenants) > 0 then
      execute $q$select min(x.m) from unnest($1) t(scope_id)
        cross join lateral (select min(l."event_type") as m from "better_supabase"."audit_events" l
          where l."tenant_id" = t.scope_id and l."event_type" > $2) x$q$
      into v_next
      using for_tenants, coalesce(v_types[cardinality(v_types)], '');
    else
      execute $q$select min(l."event_type") from "better_supabase"."audit_events" l where l."event_type" > $1$q$
      into v_next
      using coalesce(v_types[cardinality(v_types)], '');
    end if;
    exit when v_next is null;
    v_types := v_types || v_next;
    exit when cardinality(v_types) >= 500;
  end loop;
  return v_types;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.count_audit_events (
  for_tenants         uuid[]                   DEFAULT NULL::uuid[],
  for_event_types     text[]                   DEFAULT NULL::text[],
  for_actors          uuid[]                   DEFAULT NULL::uuid[],
  for_target_types    text[]                   DEFAULT NULL::text[],
  for_records         text[]                   DEFAULT NULL::text[],
  for_categories      text[]                   DEFAULT NULL::text[],
  for_outcomes        text[]                   DEFAULT NULL::text[],
  search              text                     DEFAULT NULL::text,
  for_sources         text[]                   DEFAULT NULL::text[],
  for_actor_kinds     text[]                   DEFAULT NULL::text[],
  for_correlation_ids text[]                   DEFAULT NULL::text[],
  since               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  cap                 integer                  DEFAULT NULL::integer
)
  RETURNS bigint
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_where text := 'true';
  result bigint;
begin
  if cardinality(for_tenants) > 0 then
    v_where := v_where || $q$ and l."tenant_id" = any ($1)$q$;
  end if;
  if cardinality(for_event_types) > 0 then
    v_where := v_where || $q$ and l."event_type" = any ($2)$q$;
  end if;
  if cardinality(for_actors) > 0 then
    v_where := v_where || $q$ and l."actor_id" = any ($3)$q$;
  end if;
  if cardinality(for_target_types) > 0 then
    v_where := v_where || $q$ and l."target_type" = any ($4)$q$;
  end if;
  if cardinality(for_records) > 0 then
    v_where := v_where || $q$ and l."record_id" = any ($5)$q$;
  end if;
  if cardinality(for_categories) > 0 then
    v_where := v_where || $q$ and l."category" = any ($6)$q$;
  end if;
  if cardinality(for_outcomes) > 0 then
    v_where := v_where || $q$ and l."outcome" = any ($7)$q$;
  end if;
  if cardinality(for_sources) > 0 then
    v_where := v_where || $q$ and l."source" = any ($9)$q$;
  end if;
  if cardinality(for_actor_kinds) > 0 then
    v_where := v_where || $q$ and l."actor_kind" = any ($10)$q$;
  end if;
  if cardinality(for_correlation_ids) > 0 then
    v_where := v_where || $q$ and l."correlation_id" = any ($11)$q$;
  end if;
  if search <> '' then
    v_where := v_where || $q$ and concat_ws(' ', l."event_type", l."summary", l."target_label", l."actor_label", l."tenant_label", l."record_id", l."table_name") ilike '%' || replace(replace(replace($8, '\', '\\'), '%', '\%'), '_', '\_') || '%'$q$;
  end if;
  if since is not null then
    v_where := v_where || $q$ and l."occurred_at" >= $12$q$;
  end if;
  if until is not null then
    v_where := v_where || $q$ and l."occurred_at" < $13$q$;
  end if;
  -- With cap the count stops there: a result equal to cap means "cap or more",
  -- and a filtered view over a large log never counts every match (ADR 0425).
  execute $q$select count(*) from (select 1 from "better_supabase"."audit_events" l where $q$ || v_where
    || case when cap is null then '' else format(' limit %s', greatest(cap, 1)) end || $q$) x$q$
  into result
  using for_tenants, for_event_types, for_actors, for_target_types, for_records, for_categories, for_outcomes, search, for_sources, for_actor_kinds, for_correlation_ids, since, until;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_audit_event (
  entry_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  result jsonb;
begin
  execute $q$select $q$ || $e$jsonb_build_object('id', l."id", 'table', l."table_name", 'record', l."record_id", 'op', l."op", 'old', l."old_record", 'new', l."new_record", 'changed', l."changed", 'actorId', l."actor_id", 'actorRole', l."actor_role", 'actorKind', l."actor_kind", 'actorLabel', l."actor_label", 'tenant', l."tenant_id", 'tenantLabel', l."tenant_label", 'occurredAt', l."occurred_at", 'impersonatedBy', l."impersonated_by", 'impersonationReason', l."impersonation_reason", 'supportSession', l."support_session_id", 'eventType', l."event_type", 'category', l."category", 'outcome', l."outcome") || jsonb_build_object('source', l."source", 'targetType', l."target_type", 'targetLabel', l."target_label", 'summary', l."summary", 'requestId', l."request_id", 'correlationId', l."correlation_id", 'scope', l."scope", 'metadata', l."metadata")$e$ || $q$ from "better_supabase"."audit_events" l where l."id" = $1$q$
  into result
  using entry_id::bigint;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_audit_events (
  for_tenants         uuid[]                   DEFAULT NULL::uuid[],
  for_event_types     text[]                   DEFAULT NULL::text[],
  for_actors          uuid[]                   DEFAULT NULL::uuid[],
  for_target_types    text[]                   DEFAULT NULL::text[],
  for_records         text[]                   DEFAULT NULL::text[],
  for_categories      text[]                   DEFAULT NULL::text[],
  for_outcomes        text[]                   DEFAULT NULL::text[],
  search              text                     DEFAULT NULL::text,
  for_sources         text[]                   DEFAULT NULL::text[],
  for_actor_kinds     text[]                   DEFAULT NULL::text[],
  for_correlation_ids text[]                   DEFAULT NULL::text[],
  since               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until               timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  cursor_at           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  cursor_id           text                     DEFAULT NULL::text,
  max_items           integer                  DEFAULT 50,
  ascending           boolean                  DEFAULT false,
  skip                integer                  DEFAULT 0,
  entry_fields        text                     DEFAULT 'full'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_where text := 'true';
  v_order text := case when ascending then 'asc' else 'desc' end;
  v_skip text := '';
  v_entry text;
  result jsonb;
begin
  -- 'summary' leaves out the old and new record, the changed columns and the
  -- metadata, so a page of a busy log stays small. get_audit_event returns the
  -- full entry.
  v_entry := case when entry_fields = 'summary'
    then $e$jsonb_build_object('id', l."id", 'table', l."table_name", 'record', l."record_id", 'op', l."op", 'actorId', l."actor_id", 'actorRole', l."actor_role", 'actorKind', l."actor_kind", 'actorLabel', l."actor_label", 'tenant', l."tenant_id", 'tenantLabel', l."tenant_label", 'occurredAt', l."occurred_at", 'impersonatedBy', l."impersonated_by", 'impersonationReason', l."impersonation_reason", 'supportSession', l."support_session_id", 'eventType', l."event_type", 'category', l."category", 'outcome', l."outcome", 'source', l."source", 'targetType', l."target_type", 'targetLabel', l."target_label") || jsonb_build_object('summary', l."summary", 'requestId', l."request_id", 'correlationId', l."correlation_id", 'scope', l."scope")$e$
    else $e$jsonb_build_object('id', l."id", 'table', l."table_name", 'record', l."record_id", 'op', l."op", 'old', l."old_record", 'new', l."new_record", 'changed', l."changed", 'actorId', l."actor_id", 'actorRole', l."actor_role", 'actorKind', l."actor_kind", 'actorLabel', l."actor_label", 'tenant', l."tenant_id", 'tenantLabel', l."tenant_label", 'occurredAt', l."occurred_at", 'impersonatedBy', l."impersonated_by", 'impersonationReason', l."impersonation_reason", 'supportSession', l."support_session_id", 'eventType', l."event_type", 'category', l."category", 'outcome', l."outcome") || jsonb_build_object('source', l."source", 'targetType', l."target_type", 'targetLabel', l."target_label", 'summary', l."summary", 'requestId', l."request_id", 'correlationId', l."correlation_id", 'scope', l."scope", 'metadata', l."metadata")$e$
  end;
  if cardinality(for_tenants) > 0 then
    v_where := v_where || $q$ and l."tenant_id" = any ($1)$q$;
  end if;
  if cardinality(for_event_types) > 0 then
    v_where := v_where || $q$ and l."event_type" = any ($2)$q$;
  end if;
  if cardinality(for_actors) > 0 then
    v_where := v_where || $q$ and l."actor_id" = any ($3)$q$;
  end if;
  if cardinality(for_target_types) > 0 then
    v_where := v_where || $q$ and l."target_type" = any ($4)$q$;
  end if;
  if cardinality(for_records) > 0 then
    v_where := v_where || $q$ and l."record_id" = any ($5)$q$;
  end if;
  if cardinality(for_categories) > 0 then
    v_where := v_where || $q$ and l."category" = any ($6)$q$;
  end if;
  if cardinality(for_outcomes) > 0 then
    v_where := v_where || $q$ and l."outcome" = any ($7)$q$;
  end if;
  if cardinality(for_sources) > 0 then
    v_where := v_where || $q$ and l."source" = any ($9)$q$;
  end if;
  if cardinality(for_actor_kinds) > 0 then
    v_where := v_where || $q$ and l."actor_kind" = any ($10)$q$;
  end if;
  if cardinality(for_correlation_ids) > 0 then
    v_where := v_where || $q$ and l."correlation_id" = any ($11)$q$;
  end if;
  if search <> '' then
    v_where := v_where || $q$ and concat_ws(' ', l."event_type", l."summary", l."target_label", l."actor_label", l."tenant_label", l."record_id", l."table_name") ilike '%' || replace(replace(replace($8, '\', '\\'), '%', '\%'), '_', '\_') || '%'$q$;
  end if;
  if since is not null then
    v_where := v_where || $q$ and l."occurred_at" >= $12$q$;
  end if;
  if until is not null then
    v_where := v_where || $q$ and l."occurred_at" < $13$q$;
  end if;
  if cursor_at is not null then
    v_where := v_where || case when ascending
      then $q$ and (l."occurred_at", l."id") > ($14, $15::bigint)$q$
      else $q$ and (l."occurred_at", l."id") < ($14, $15::bigint)$q$
    end;
  elsif coalesce(skip, 0) > 0 then
    v_skip := ' offset $17';
  end if;
  -- Only the filters passed reach the query, so the planner sees no
  -- "is null or" branches and can use the (tenant, occurred_at) index.
  execute $q$select coalesce(jsonb_agg(x.entry order by x.occurred_at $q$ || v_order || $q$, x.id $q$ || v_order || $q$), '[]')
  from (
    select $q$ || v_entry || $q$ as entry, l."occurred_at" as occurred_at, l."id" as id
    from "better_supabase"."audit_events" l
    where $q$ || v_where || $q$
    order by l."occurred_at" $q$ || v_order || $q$, l."id" $q$ || v_order || $q$
    limit $16$q$ || v_skip || $q$
  ) x$q$
  into result
  using for_tenants, for_event_types, for_actors, for_target_types, for_records, for_categories, for_outcomes, search, for_sources, for_actor_kinds, for_correlation_ids, since, until, cursor_at, cursor_id, least(greatest(coalesce(max_items, 50), 1), 1000), greatest(coalesce(skip, 0), 0);
  return result;
end;
$function$;

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
    v_where := v_where || $q$ and concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike $5$q$;
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
    least(coalesce(list_notifications.max_items, 50), 200);
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
  total_cap     integer                  DEFAULT 10000
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_where text;
  v_limit integer := least(greatest(coalesce(notification_page.max_items, 50), 1), 200);
  v_items jsonb;
  v_total bigint;
  v_args_cap integer := notification_page.total_cap;
begin
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
    v_where := v_where || $q$ and concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike $5$q$;
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
  -- One row more than the page says whether an older page exists, and the
  -- total stops counting at total_cap (null counts every row), so a large
  -- inbox never counts all of it. Pass before and before_id to page by key
  -- instead of skip.
  execute $q$select coalesce(jsonb_agg(p.item order by p.created_at desc, p.id desc), '[]')
  from (
    select jsonb_build_object('id', rc."id", 'event_id', ev."id", 'type', ev."type", 'data', ev."data", 'created_at', rc."created_at", 'read_at', rc."read_at", 'tenant', ev."tenant_id", 'actor_id', ev."actor_id", 'subject_type', ev."subject_type", 'subject_id', ev."subject_id", 'subject_label', ev."subject_label", 'summary', ev."summary", 'action_path', ev."action_path", 'actions', ev."actions", 'priority', ev."priority", 'resolved_at', rc."resolved_at", 'resolution', rc."resolution") as item, rc."created_at" as created_at, rc."id" as id
    from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where $q$ || v_where || $q$
    order by rc."created_at" desc, rc."id" desc
    offset $11
    limit $12 + 1
  ) p$q$
  into v_items
  using auth.uid(), notification_page.tenant, notification_page.types, notification_page.subject_types,
    case when btrim(coalesce(notification_page.search, '')) = '' then null else '%' || replace(replace(replace(btrim(notification_page.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%' end, notification_page.read, notification_page.resolved, notification_page.dismissed,
    notification_page.before, coalesce(notification_page.before_id, '00000000-0000-0000-0000-000000000000'::uuid),
    greatest(coalesce(notification_page.skip, 0), 0), v_limit;
  execute $q$select count(*) from (
    select 1 from "better_supabase"."notification_recipients" rc
    join "better_supabase"."notification_events" ev on ev."id" = rc."event_id"
    where $q$ || v_where || case when v_args_cap is null then '' else format(' limit %s', greatest(v_args_cap, 1)) end || $q$
  ) c$q$
  into v_total
  using auth.uid(), notification_page.tenant, notification_page.types, notification_page.subject_types,
    case when btrim(coalesce(notification_page.search, '')) = '' then null else '%' || replace(replace(replace(btrim(notification_page.search), chr(92), chr(92) || chr(92)), '%', chr(92) || '%'), '_', chr(92) || '_') || '%' end, notification_page.read, notification_page.resolved, notification_page.dismissed,
    notification_page.before, coalesce(notification_page.before_id, '00000000-0000-0000-0000-000000000000'::uuid);
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(x.value order by x.ordinality) from jsonb_array_elements(v_items) with ordinality x(value, ordinality) where x.ordinality <= v_limit), '[]'),
    'hasMore', jsonb_array_length(v_items) > v_limit,
    'total', v_total,
    'totalCapped', v_args_cap is not null and v_total >= v_args_cap
  );
end;
$function$;

CREATE INDEX audit_events_actor_idx ON better_supabase.audit_events USING btree (tenant_id, actor_id, occurred_at DESC, id DESC);

CREATE INDEX audit_events_event_type_idx ON better_supabase.audit_events USING btree (tenant_id, event_type, occurred_at DESC, id DESC);

CREATE INDEX audit_events_organization_idx ON better_supabase.audit_events USING btree (tenant_id, occurred_at DESC, id DESC);

REVOKE ALL ON FUNCTION "api"."audit_event_types"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."audit_event_types"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "api"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, integer)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, integer)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_audit_event"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_audit_event"(text) TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "api"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean, integer, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean, integer, text)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."notification_counts"(uuid, text[], integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."notification_counts"(uuid, text[], integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean, timestamp WITH time zone, uuid, integer) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "api"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean, timestamp WITH time zone, uuid, integer)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."audit_event_types"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."audit_event_types"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "better_supabase"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, integer)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, integer)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_audit_event"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_audit_event"(text) TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean, integer, text)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean, integer, text)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_notifications"(uuid, text, text[], timestamp WITH time zone, integer, uuid, text[], text, boolean, boolean, boolean) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."list_notifications"(uuid, text, text[], timestamp WITH time zone, integer, uuid, text[], text, boolean, boolean, boolean)
  TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."notification_counts"(uuid, text[], integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."notification_counts"(uuid, text[], integer) TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean, timestamp WITH time zone, uuid, integer)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer, boolean, boolean, boolean, timestamp WITH time zone, uuid, integer)
  TO "authenticated", "service_role";
