SET local check_function_bodies = off;

DROP FUNCTION "api"."invoice_e_endpoints"(uuid);

CREATE OR REPLACE FUNCTION api.e_invoice_endpoints (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."e_invoice_endpoints"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_pipeline_stage (
  stage   uuid,
  move_to uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_pipeline uuid;
  v_subject_type text;
  v_outcome text;
  v_used boolean;
  v_stage uuid := archive_pipeline_stage.stage;
  v_to uuid := archive_pipeline_stage.move_to;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."pipeline_id", x."outcome", y."subject_type"
    into v_tenant, v_pipeline, v_outcome, v_subject_type
  from "better_supabase"."pipeline_stages" x join "better_supabase"."pipelines" y on y."id" = x."pipeline_id"
  where x."id" = archive_pipeline_stage.stage and x."archived_at" is null;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'pipelines.manage'), false)) then
    raise exception 'not allowed to manage pipelines' using errcode = '42501', hint = 'PIPELINE_FORBIDDEN';
  end if;
  case v_subject_type
    when 'deal' then
      perform 1 from "better_supabase"."deals" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    when 'work_item' then
      perform 1 from "better_supabase"."work_items" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    when 'maintenance_request' then
      perform 1 from "better_supabase"."maintenance_requests" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    when 'application' then
      perform 1 from "better_supabase"."applications" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    when 'case' then
      perform 1 from "better_supabase"."cases" r where r."stage_id" = archive_pipeline_stage.stage limit 1;
      v_used := found;
    else
      v_used := false;
  end case;
  if archive_pipeline_stage.move_to is not null then
    if archive_pipeline_stage.move_to = archive_pipeline_stage.stage or not exists (
      select 1 from "better_supabase"."pipeline_stages" x
      where x."id" = archive_pipeline_stage.move_to and x."pipeline_id" = v_pipeline and x."archived_at" is null
    ) then
      raise exception 'move_to must be another active stage of the same pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_REPLACEMENT_INVALID';
    end if;
  end if;
  if v_used and archive_pipeline_stage.move_to is null then
    raise exception 'records are in this stage; move them first or name a stage to move them to' using errcode = '23503', hint = 'PIPELINE_STAGE_IN_USE';
  end if;
  if v_outcome = 'open' and not exists (
    select 1 from "better_supabase"."pipeline_stages" x where x."pipeline_id" = v_pipeline and x."outcome" = 'open'
      and x."archived_at" is null and x."id" <> archive_pipeline_stage.stage
  ) then
    raise exception 'a pipeline keeps at least one open stage' using errcode = '23514', hint = 'PIPELINE_LAST_OPEN_STAGE';
  end if;
  if v_used then
    -- The stage trigger lets this one change through even where the allowed
    -- stage changes would not.
    perform set_config('better_supabase.lane_move', v_stage::text || ':' || v_to::text, true);
    case v_subject_type
    when 'deal' then
      update "better_supabase"."deals" r set "stage_id" = archive_pipeline_stage.move_to where r."stage_id" = archive_pipeline_stage.stage;
    when 'work_item' then
      update "better_supabase"."work_items" r set "stage_id" = archive_pipeline_stage.move_to where r."stage_id" = archive_pipeline_stage.stage;
    when 'maintenance_request' then
      update "better_supabase"."maintenance_requests" r set "stage_id" = archive_pipeline_stage.move_to where r."stage_id" = archive_pipeline_stage.stage;
    when 'application' then
      update "better_supabase"."applications" r set "stage_id" = archive_pipeline_stage.move_to where r."stage_id" = archive_pipeline_stage.stage;
    when 'case' then
      update "better_supabase"."cases" r set "stage_id" = archive_pipeline_stage.move_to where r."stage_id" = archive_pipeline_stage.stage;
    else
      null;
  end case;
    perform set_config('better_supabase.lane_move', '', true);
  end if;
  update "better_supabase"."pipeline_stages" x set "archived_at" = now(), "updated_at" = now() where x."id" = archive_pipeline_stage.stage;
  perform "better_supabase".emit_event('pipeline_stage.archived', jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage), 'pipelines/' || v_pipeline::text, (v_tenant::text)::text, null, 'better-supabase/pipelines');
  perform better_supabase.audit_event(
    event_type => 'pipeline_stage.archived',
    category => 'configuration',
    target_type => 'pipeline_stage',
    record_id => v_stage::text,
    summary => 'archived a pipeline stage',
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'pipelineId', v_pipeline, 'stageId', v_stage)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event (
  event_type           text,
  category             text  DEFAULT NULL::text,
  outcome              text  DEFAULT 'success'::text,
  source               text  DEFAULT NULL::text,
  target_type          text  DEFAULT NULL::text,
  record_id            text  DEFAULT NULL::text,
  tenant               uuid  DEFAULT NULL::uuid,
  metadata             jsonb DEFAULT '{}'::jsonb,
  idempotency_key      text  DEFAULT NULL::text,
  restricted           jsonb DEFAULT NULL::jsonb,
  actor_id             uuid  DEFAULT NULL::uuid,
  summary              text  DEFAULT NULL::text,
  target_label         text  DEFAULT NULL::text,
  correlation_id       text  DEFAULT NULL::text,
  actor_kind           text  DEFAULT NULL::text,
  actor_label          text  DEFAULT NULL::text,
  ip                   inet  DEFAULT NULL::inet,
  user_agent           text  DEFAULT NULL::text,
  session_id           text  DEFAULT NULL::text,
  request_id           text  DEFAULT NULL::text,
  scope                text  DEFAULT NULL::text,
  support_session      uuid  DEFAULT NULL::uuid,
  impersonated_by      uuid  DEFAULT NULL::uuid,
  impersonation_reason text  DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing text;
  v_integration boolean := better_supabase.import_run() is not null;
  entry_id "better_supabase"."audit_events"."id"%type;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set blocks.audit.options.restricted to true.';
  end if;
  -- imports.audit 'summary' (ADR 0141): the run audits per entity at its end.
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    actor_id := auth.uid();
    actor_kind := null;
    actor_label := null;
    ip := null;
    user_agent := null;
    session_id := null;
    request_id := null;
    scope := null;
    if (select auth.jwt()) -> 'act' is not null or impersonated_by is distinct from auth.uid() then
      support_session := null;
      impersonated_by := null;
      impersonation_reason := null;
    end if;
  elsif actor_id is null then
    actor_id := coalesce(auth.uid(), better_supabase.acting_member());
  end if;
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "better_supabase"."audit_events" l
    where l."idempotency_key" = audit_event.idempotency_key
      and l."tenant_id" is not distinct from audit_event.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "metadata", "idempotency_key", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
  values (
    null,
    record_id,
    'event',
    actor_id,
    coalesce(auth.jwt() ->> 'role', current_user),
    tenant,
    coalesce(audit_event.impersonated_by, case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end),
    coalesce(audit_event.impersonation_reason, auth.jwt() -> 'act' ->> 'reason'),
    coalesce(audit_event.support_session, case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end),
    event_type,
    coalesce(category, 'system'),
    coalesce(outcome, 'success'),
    coalesce(source, 'app'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key,
    coalesce(actor_kind, case
      when v_integration then 'integration'
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end),
    coalesce(actor_label, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')),
    (select o."name"::text from "public"."organizations" o where o."id" = tenant),
    target_label,
    summary,
    coalesce(better_supabase.request_id_or_null(request_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-request-id')))),
    coalesce(better_supabase.request_id_or_null(correlation_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-correlation-id')))),
    coalesce(audit_event.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  if audit_event.target_type is not null and audit_event.record_id is not null then
    perform pg_catalog.set_config('better_supabase.recorded', coalesce(pg_catalog.current_setting('better_supabase.recorded', true), '') || E'\n' || audit_event.target_type || ':' || audit_event.record_id, true);
  end if;
  return entry_id::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_event_trusted (
  event_type           text,
  category             text  DEFAULT NULL::text,
  outcome              text  DEFAULT 'success'::text,
  source               text  DEFAULT NULL::text,
  target_type          text  DEFAULT NULL::text,
  record_id            text  DEFAULT NULL::text,
  tenant               uuid  DEFAULT NULL::uuid,
  metadata             jsonb DEFAULT '{}'::jsonb,
  idempotency_key      text  DEFAULT NULL::text,
  restricted           jsonb DEFAULT NULL::jsonb,
  actor_id             uuid  DEFAULT NULL::uuid,
  summary              text  DEFAULT NULL::text,
  target_label         text  DEFAULT NULL::text,
  correlation_id       text  DEFAULT NULL::text,
  actor_kind           text  DEFAULT NULL::text,
  actor_label          text  DEFAULT NULL::text,
  ip                   inet  DEFAULT NULL::inet,
  user_agent           text  DEFAULT NULL::text,
  session_id           text  DEFAULT NULL::text,
  request_id           text  DEFAULT NULL::text,
  scope                text  DEFAULT NULL::text,
  support_session      uuid  DEFAULT NULL::uuid,
  impersonated_by      uuid  DEFAULT NULL::uuid,
  impersonation_reason text  DEFAULT NULL::text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing text;
  v_integration boolean := better_supabase.import_run() is not null;
  entry_id "better_supabase"."audit_events"."id"%type;
begin
  if restricted is not null or ip is not null or user_agent is not null or session_id is not null then
    raise exception 'audit_event got restricted details, and the audit module has no restricted table'
      using errcode = '22023', hint = 'Set blocks.audit.options.restricted to true.';
  end if;
  -- imports.audit 'summary' (ADR 0141): the run audits per entity at its end.
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  actor_id := coalesce(actor_id, auth.uid());
  if idempotency_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.audit_event'), pg_catalog.hashtext(coalesce(tenant::text, '') || ':' || idempotency_key));
    select l."id"::text into existing
    from "better_supabase"."audit_events" l
    where l."idempotency_key" = audit_event_trusted.idempotency_key
      and l."tenant_id" is not distinct from audit_event_trusted.tenant
    limit 1;
    if existing is not null then
      return existing;
    end if;
  end if;
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "metadata", "idempotency_key", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
  values (
    null,
    record_id,
    'event',
    actor_id,
    coalesce(auth.jwt() ->> 'role', current_user),
    tenant,
    coalesce(audit_event_trusted.impersonated_by, case when auth.jwt() -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'sub')::uuid end),
    coalesce(audit_event_trusted.impersonation_reason, auth.jwt() -> 'act' ->> 'reason'),
    coalesce(audit_event_trusted.support_session, case when auth.jwt() -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (auth.jwt() -> 'act' ->> 'session_id')::uuid end),
    event_type,
    coalesce(category, 'system'),
    coalesce(outcome, 'success'),
    coalesce(source, 'app'),
    target_type,
    coalesce(metadata, '{}'),
    idempotency_key,
    coalesce(actor_kind, case
      when v_integration then 'integration'
      when coalesce(auth.jwt() ->> 'role', '') = 'service_role' then 'service'
      when auth.jwt() -> 'act' ->> 'kind' = 'support' then 'support'
      when auth.jwt() -> 'act' is not null then 'impersonation'
      when auth.jwt() ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end),
    coalesce(actor_label, coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() ->> 'email')),
    (select o."name"::text from "public"."organizations" o where o."id" = tenant),
    target_label,
    summary,
    coalesce(better_supabase.request_id_or_null(request_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-request-id')))),
    coalesce(better_supabase.request_id_or_null(correlation_id), coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null(better_supabase.request_header('x-correlation-id')))),
    coalesce(audit_event_trusted.scope, case when tenant is null then 'platform' else 'tenant' end)
  )
  returning "id" into entry_id;
  if audit_event_trusted.target_type is not null and audit_event_trusted.record_id is not null then
    perform pg_catalog.set_config('better_supabase.recorded', coalesce(pg_catalog.current_setting('better_supabase.recorded', true), '') || E'\n' || audit_event_trusted.target_type || ':' || audit_event_trusted.record_id, true);
  end if;
  return entry_id::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_row_change()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  entry record;
  settings jsonb;
  entry_id "better_supabase"."audit_events"."id"%type;
  old_row jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  new_row jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  row_data jsonb := coalesce(new_row, old_row);
  changed_columns text[];
  changed_values jsonb;
  row_tenant uuid;
  v_jwt jsonb := auth.jwt();
  v_headers jsonb := better_supabase.request_headers();
  v_integration boolean := better_supabase.import_run() is not null;
  v_label text;
  path_value text;
  path_step jsonb;
begin
  -- An import run with imports.audit 'summary' audits one entry per entity at
  -- its end instead of one per row (ADR 0141).
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  if tg_nargs > 0 then
    settings := tg_argv[0]::jsonb;
    select array(select jsonb_array_elements_text(coalesce(settings -> 'ignore', '[]'))) as ignore,
      coalesce(
        nullif(array(select jsonb_array_elements_text(coalesce(settings -> 'key_columns', '[]'))), '{}'),
        (select array_agg(c.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
         where i.indrelid = tg_relid and i.indisprimary),
        '{id}'
      ) as key_columns,
      array(select jsonb_array_elements_text(coalesce(settings -> 'redact', '[]'))) as redact,
      settings ->> 'category' as category, settings ->> 'event_prefix' as event_prefix,
      settings ->> 'target_type' as target_type, settings ->> 'tenant_column' as tenant_column,
      settings ->> 'label_column' as label_column,
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function
    into entry;
  else
    select coalesce(a."ignore", '{}') as ignore, coalesce(a."key_columns", '{id}') as key_columns,
      coalesce(a."redact", '{}') as redact, a."category" as category,
      a."event_prefix" as event_prefix, a."target_type" as target_type,
      a."tenant_column" as tenant_column, a."label_column" as label_column,
      null::jsonb as tenant_path, null::text as tenant_function
    into entry
    from (select 1) one
    left join "better_supabase"."audited_tables" a on a."target" = tg_relid::regclass;
  end if;
  if position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0 then
    return null;
  end if;
  row_tenant := case when row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end;
  -- A child row without a tenant column: follow the foreign-key path
  -- registered through tenant_path, then the tenant function.
  if row_tenant is null and entry.tenant_path is not null then
    path_value := row_data ->> (entry.tenant_path ->> 'column');
    for path_step in select * from jsonb_array_elements(entry.tenant_path -> 'steps') loop
      exit when path_value is null;
      execute format('select %I::text from %s where %I::text = $1 limit 1',
        path_step ->> 'read', path_step ->> 'table', path_step ->> 'ref')
        into path_value using path_value;
    end loop;
    row_tenant := case when path_value ~* '^[0-9a-f-]{36}$' then (path_value)::uuid end;
  end if;
  if row_tenant is null and entry.tenant_function is not null then
    execute format('select %s($1)::text', (entry.tenant_function::regprocedure)::oid::regproc) into path_value using row_data;
    row_tenant := case when path_value ~* '^[0-9a-f-]{36}$' then (path_value)::uuid end;
  end if;
  if row_tenant is not null then
    v_label := better_supabase.memo_get('audit.tenant_label.t' || replace(row_tenant::text, '-', ''));
    if v_label is null then
      v_label := (select o."name"::text from "public"."organizations" o where o."id" = row_tenant);
      perform better_supabase.memo_set('audit.tenant_label.t' || replace(row_tenant::text, '-', ''), coalesce(v_label, ''));
    end if;
  end if;
  old_row := old_row - entry.ignore;
  new_row := new_row - entry.ignore;
  if tg_op = 'UPDATE' then
    select array_agg(key order by key) into changed_columns
    from jsonb_each(new_row) n
    where n.value is distinct from old_row -> n.key;
    if changed_columns is null then
      return null;
    end if;
  end if;
  -- Redacted columns stay in changed, with their values masked.
  old_row := old_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where old_row ? k), '{}');
  new_row := new_row || coalesce((select jsonb_object_agg(k, '"[redacted]"'::jsonb) from unnest(entry.redact) k where new_row ? k), '{}');
  insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
  values (
    tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    lower(tg_op),
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    v_label,
    row_data ->> entry.label_column,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
  )
  returning "id" into entry_id;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_statement_change()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  entry record;
  settings jsonb;
  v_jwt jsonb := auth.jwt();
  v_headers jsonb := better_supabase.request_headers();
  v_integration boolean := better_supabase.import_run() is not null;
begin
  if v_integration and current_setting('better_supabase.import_audit', true) = 'summary' then
    return null;
  end if;
  if tg_nargs > 0 then
    settings := tg_argv[0]::jsonb;
    select array(select jsonb_array_elements_text(coalesce(settings -> 'ignore', '[]'))) as ignore,
      coalesce(
        nullif(array(select jsonb_array_elements_text(coalesce(settings -> 'key_columns', '[]'))), '{}'),
        (select array_agg(c.attname::text order by k.ord)
         from pg_catalog.pg_index i
         cross join lateral unnest(i.indkey) with ordinality k(attnum, ord)
         join pg_catalog.pg_attribute c on c.attrelid = i.indrelid and c.attnum = k.attnum
         where i.indrelid = tg_relid and i.indisprimary),
        '{id}'
      ) as key_columns,
      array(select jsonb_array_elements_text(coalesce(settings -> 'redact', '[]'))) as redact,
      settings ->> 'category' as category, settings ->> 'event_prefix' as event_prefix,
      settings ->> 'target_type' as target_type, settings ->> 'tenant_column' as tenant_column,
      settings ->> 'label_column' as label_column,
      settings -> 'tenant_path' as tenant_path, settings ->> 'tenant_function' as tenant_function
    into entry;
  else
    select coalesce(a."ignore", '{}') as ignore, coalesce(a."key_columns", '{id}') as key_columns,
      coalesce(a."redact", '{}') as redact, a."category" as category,
      a."event_prefix" as event_prefix, a."target_type" as target_type,
      a."tenant_column" as tenant_column, a."label_column" as label_column,
      null::jsonb as tenant_path, null::text as tenant_function
    into entry
    from (select 1) one
    left join "better_supabase"."audited_tables" a on a."target" = tg_relid::regclass;
  end if;
  if tg_op = 'INSERT' then
    with src as (
      select null::jsonb as old_row, to_jsonb(n) as new_row from new_rows n
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, case when c.row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (c.row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
    select tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    op,
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then 'updated' else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    l.label,
    row_data ->> entry.label_column,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
    from final
    left join labels l on l.tenant_key is not distinct from final.row_tenant;
  elsif tg_op = 'DELETE' then
    with src as (
      select to_jsonb(o) as old_row, null::jsonb as new_row from old_rows o
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, case when c.row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (c.row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
    select tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    op,
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then 'updated' else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    l.label,
    row_data ->> entry.label_column,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
    from final
    left join labels l on l.tenant_key is not distinct from final.row_tenant;
  else
    with src as (
      select o.j as old_row, n.j as new_row
      from (select to_jsonb(r) as j, (select string_agg(to_jsonb(r) ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)) as k from old_rows r) o
      full join (select to_jsonb(r) as j, (select string_agg(to_jsonb(r) ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)) as k from new_rows r) n on o.k = n.k
    ), paired as (
      select case when s.old_row is null then 'insert' when s.new_row is null then 'delete' else 'update' end as op,
        coalesce(s.new_row, s.old_row) as row_data,
        s.old_row - entry.ignore as old_row, s.new_row - entry.ignore as new_row
      from src s
    ), changed as (
      select p.*, case when p.op = 'update' then (
          select array_agg(e.key order by e.key) from jsonb_each(p.new_row) e
          where e.value is distinct from p.old_row -> e.key
        ) end as changed_columns
      from paired p
    ), kept as (
      select c.*, case when c.row_data ->> coalesce(entry.tenant_column, 'organization_id') ~* '^[0-9a-f-]{36}$' then (c.row_data ->> coalesce(entry.tenant_column, 'organization_id'))::uuid end as row_tenant
      from changed c
      where (c.op <> 'update' or c.changed_columns is not null)
        and not (position(E'\n' || coalesce(entry.target_type, tg_table_name) || ':' || coalesce((select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)), '') || E'\n' in coalesce(current_setting('better_supabase.recorded', true), '') || E'\n') > 0)
    ), final as (
      select k.op, k.row_data, k.changed_columns, k.row_tenant,
        k.old_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.old_row ? r), '{}') as old_row,
        k.new_row || coalesce((select jsonb_object_agg(r, '"[redacted]"'::jsonb) from unnest(entry.redact) r where k.new_row ? r), '{}') as new_row
      from kept k
    ), labels as (
      select t.row_tenant as tenant_key, (select o."name"::text from "public"."organizations" o where o."id" = t.row_tenant) as label
      from (select distinct row_tenant from kept) t
    )
    insert into "better_supabase"."audit_events" ("table_name", "record_id", "op", "old_record", "new_record", "changed", "actor_id", "actor_role", "tenant_id", "impersonated_by", "impersonation_reason", "support_session_id", "event_type", "category", "outcome", "source", "target_type", "actor_kind", "actor_label", "tenant_label", "target_label", "summary", "request_id", "correlation_id", "scope")
    select tg_table_schema || '.' || tg_table_name,
    (select string_agg(row_data ->> k.name, ',' order by k.ord) from unnest(entry.key_columns) with ordinality k(name, ord)),
    op,
    old_row,
    new_row,
    changed_columns,
    coalesce(auth.uid(), better_supabase.acting_member()),
    coalesce(v_jwt ->> 'role', current_user),
    row_tenant,
    case when v_jwt -> 'act' ->> 'sub' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'sub')::uuid end,
    v_jwt -> 'act' ->> 'reason',
    case when v_jwt -> 'act' ->> 'session_id' ~ '^[0-9a-f-]{36}$' then (v_jwt -> 'act' ->> 'session_id')::uuid end,
    coalesce(entry.event_prefix, tg_table_name) || '.' || case op when 'insert' then 'created' when 'update' then 'updated' else 'deleted' end,
    coalesce(entry.category, 'data'),
    'success',
    'database',
    coalesce(entry.target_type, tg_table_name),
    case
      when v_integration then 'integration'
      when coalesce(v_jwt ->> 'role', '') = 'service_role' then 'service'
      when v_jwt -> 'act' ->> 'kind' = 'support' then 'support'
      when v_jwt -> 'act' is not null then 'impersonation'
      when v_jwt ->> 'client_id' is not null then 'oauth-client'
      when auth.uid() is not null then 'user'
      else 'system'
    end,
    coalesce(v_jwt -> 'user_metadata' ->> 'full_name', v_jwt ->> 'email'),
    l.label,
    row_data ->> entry.label_column,
    null,
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.request_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-request-id'))),
    coalesce(better_supabase.request_id_or_null(current_setting('better_supabase.correlation_id', true)), better_supabase.request_id_or_null((v_headers ->> 'x-correlation-id'))),
    case when row_tenant is null then 'platform' else 'tenant' end
    from final
    left join labels l on l.tenant_key is not distinct from final.row_tenant;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_application()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
  -- The owner watches the record; a level they already chose stays.
  if new."owner_id" is not null and (tg_op = 'INSERT' or new."owner_id" is distinct from old."owner_id") then
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_id", 'application', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'application', new."job_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'application'
    and p."scope_id" is not distinct from new."job_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('better_supabase.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'application', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'application' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_id")
    values (new."tenant_id", 'application', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'application', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'application',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'application', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  -- The owner watches the record; a level they already chose stays.
  if new."owner_id" is not null and (tg_op = 'INSERT' or new."owner_id" is distinct from old."owner_id") then
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_id", 'application', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_case()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'case', new."kind_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'case'
    and p."scope_id" is not distinct from new."kind_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('better_supabase.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'case', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'case' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_id")
    values (new."tenant_id", 'case', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'case', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'case',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'case', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_deal()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
  -- The owner watches the record; a level they already chose stays.
  if new."owner_id" is not null and (tg_op = 'INSERT' or new."owner_id" is distinct from old."owner_id") then
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'deal', null);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'deal'
    and p."scope_id" is not distinct from null;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('better_supabase.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'deal', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'deal' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_id")
    values (new."tenant_id", 'deal', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, new."amount", new."currency", auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'deal', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'deal',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'deal', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  -- The owner watches the record; a level they already chose stays.
  if new."owner_id" is not null and (tg_op = 'INSERT' or new."owner_id" is distinct from old."owner_id") then
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (new."tenant_id", new."owner_id", 'deal', new."id"::text, 'participating')
    on conflict do nothing;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_maintenance_request()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'maintenance_request', new."team_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'maintenance_request'
    and p."scope_id" is not distinct from new."team_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('better_supabase.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'maintenance_request', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'maintenance_request' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_id")
    values (new."tenant_id", 'maintenance_request', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'maintenance_request', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'maintenance_request',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'maintenance_request', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_pipeline_work_item()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_category text;
  v_outcome text;
  v_stage_name text;
  v_claims text;
begin
  if tg_op = 'UPDATE' and new."stage_id" is not distinct from old."stage_id" and new."pipeline_id" is not distinct from old."pipeline_id" then
    return new;
  end if;
  if new."pipeline_id" is null then
    if new."stage_id" is not null then
      select s."pipeline_id" into new."pipeline_id" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id";
    else
      new."pipeline_id" := "better_supabase"."default_pipeline"(new."tenant_id", 'work_item', new."team_id"::text);
    end if;
  end if;
  if new."stage_id" is null then
    select s."id" into new."stage_id" from "better_supabase"."pipeline_stages" s
    where s."pipeline_id" = new."pipeline_id" and s."outcome" = 'open' and s."archived_at" is null
    order by s."rank" collate "C"
    limit 1;
  end if;
  select s."category", s."outcome", s."name"
    into v_category, v_outcome, v_stage_name
  from "better_supabase"."pipeline_stages" s
  join "better_supabase"."pipelines" p on p."id" = s."pipeline_id"
  where s."id" = new."stage_id"
    and s."pipeline_id" = new."pipeline_id"
    and s."archived_at" is null
    and p."archived_at" is null
    and p."tenant_id"::text = new."tenant_id"::text
    and p."subject_type" = 'work_item'
    and p."scope_id" is not distinct from new."team_id"::text;
  if not found then
    raise exception 'the stage is not an active stage of this record''s pipeline' using errcode = '22023', hint = 'PIPELINE_STAGE_INVALID';
  end if;
  if tg_op = 'INSERT' or new."stage_id" is distinct from old."stage_id" then
    if tg_op = 'UPDATE' and old."stage_id" is not null
      and coalesce(current_setting('better_supabase.lane_move', true), '') <> old."stage_id"::text || ':' || new."stage_id"::text
      and exists (select 1 from "better_supabase"."pipeline_transitions" x where x."pipeline_id" = new."pipeline_id")
      and not exists (
        select 1 from "better_supabase"."pipeline_transitions" x
        where x."from_stage_id" = old."stage_id" and x."to_stage_id" = new."stage_id"
      ) then
      raise exception 'that stage change is not allowed in this pipeline' using errcode = '22023', hint = 'PIPELINE_TRANSITION_INVALID';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_pipeline_stage_change"(text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid, $4::uuid)', v_hook::oid::regproc)
        using 'work_item', new."id"::text, case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id";
    end if;
  end;
    new."stage_entered_at" := now();
    update "better_supabase"."pipeline_stage_history" set "exited_at" = now()
    where "subject_type" = 'work_item' and "subject_id" = new."id"::text and "exited_at" is null;
    insert into "better_supabase"."pipeline_stage_history" ("tenant_id", "subject_type", "subject_id", "pipeline_id", "from_stage_id", "to_stage_id", "stage_name", "category", "outcome", "amount", "currency", "actor_id")
    values (new."tenant_id", 'work_item', new."id"::text, new."pipeline_id", case when tg_op = 'UPDATE' then old."stage_id" end, new."stage_id", v_stage_name, v_category, v_outcome, null, null, auth.uid());
    if tg_op = 'UPDATE' then
      perform "better_supabase".emit_event('pipeline.stage_changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'work_item', 'subjectId', new."id"::text, 'pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'category', v_category, 'outcome', v_outcome), 'pipelines/' || new."pipeline_id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/pipelines');
    end if;
    if tg_op = 'UPDATE' then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'pipeline.stage_changed',
        'tenant', new."tenant_id",
        'actor', auth.uid(),
        'subject_type', 'work_item',
        'subject_id', new."id"::text,
        'summary', v_stage_name,
        'key', 'pipeline.stage_changed:' || new."id"::text || ':' || new."stage_id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('pipelineId', new."pipeline_id", 'fromStageId', old."stage_id", 'toStageId', new."stage_id", 'outcome', v_outcome)
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_pipeline_stage_change"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using 'work_item', new."id"::text, new."stage_id";
    end if;
  end;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.data_lifecycle_tables()
  RETURNS TABLE (
    subject  text,
    name     text,
    tbl      text,
    col      text,
    purge    boolean,
    omit     text[],
    exported boolean
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select t.subject, t.name, t.tbl, t.col, t.purge,
    t.omit || array(
      select a.attname::text
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(t.tbl)
        and a.attnum > 0
        and not a.attisdropped
        and a.attname ~* 'token|secret|_hash|password|api_key|license_key'
        and a.attname <> t.col
        and not a.attname = any(t.omit)
      order by a.attnum
    ) as omit,
    t.exported
  from (
  select * from (values
    ('user', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'actor_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('user', 'public.memberships', '"public"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.profiles', '"better_supabase"."profiles"', 'id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_digests', '"better_supabase"."notification_digests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_suppressions', '"better_supabase"."notification_suppressions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.user_settings', '"better_supabase"."user_settings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.guests', '"better_supabase"."guests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.waitlist_entries', '"better_supabase"."waitlist_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.invite_code_redemptions', '"better_supabase"."invite_code_redemptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.announcement_dismissals', '"better_supabase"."announcement_dismissals"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.streams', '"better_supabase"."streams"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definition_grants', '"better_supabase"."workflow_definition_grants"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_members', '"better_supabase"."inbox_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_team_members', '"better_supabase"."inbox_team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_chat_participants', '"better_supabase"."ai_chat_participants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_links', '"better_supabase"."ai_chat_links"', 'created_by', true, array['salt']::text[], true),
    ('user', 'better_supabase.ai_messages', '"better_supabase"."ai_messages"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_runs', '"better_supabase"."ai_runs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_tool_approvals', '"better_supabase"."ai_tool_approvals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_pending_inputs', '"better_supabase"."ai_pending_inputs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_feedback', '"better_supabase"."ai_message_feedback"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_shares', '"better_supabase"."ai_chat_shares"', 'created_by', true, array['token_hash']::text[], true),
    ('user', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_run_steps', '"better_supabase"."ai_run_steps"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_harness_sessions', '"better_supabase"."ai_harness_sessions"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agents', '"better_supabase"."agents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_ratings', '"better_supabase"."agent_ratings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.connector_sessions', '"better_supabase"."connector_sessions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.push_devices', '"better_supabase"."push_devices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.teams', '"better_supabase"."teams"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.team_members', '"better_supabase"."team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, array['token_hash', 'password_hash']::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_items', '"better_supabase"."approval_items"', 'decided_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.signatures', '"better_supabase"."signatures"', 'signer', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.activities', '"better_supabase"."activities"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'notifier_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'appellant_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_id', true, '{}'::text[], true),
    ('user', 'better_supabase.leases', '"better_supabase"."leases"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_regulatory_filings', '"better_supabase"."incident_regulatory_filings"', 'submitted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.courses', '"better_supabase"."courses"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversations', '"better_supabase"."conversations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.messages', '"better_supabase"."messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'edited_by', true, '{}'::text[], true),
    ('user', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.channels', '"better_supabase"."channels"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.sequences', '"better_supabase"."sequences"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'assessed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.consent_signals', '"better_supabase"."consent_signals"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.observations', '"better_supabase"."observations"', 'performer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'read_by', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'performed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'appraisee_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'calibrated_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'assignee_id', true, '{}'::text[], true),
    ('user', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'submitted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'opened_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'counted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'decided_by', true, '{}'::text[], true),
    ('user', 'better_supabase.periods', '"better_supabase"."periods"', 'closed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deadlines', '"better_supabase"."deadlines"', 'satisfied_by', true, '{}'::text[], true),
    ('user', 'better_supabase.commission_assignments', '"better_supabase"."commission_assignments"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.commissions', '"better_supabase"."commissions"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.commission_statements', '"better_supabase"."commission_statements"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.referral_codes', '"better_supabase"."referral_codes"', 'referrer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.referrals', '"better_supabase"."referrals"', 'referrer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'prescriber_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'tenant_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'tenant_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.outbox_events', '"better_supabase"."outbox_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_events', '"better_supabase"."notification_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_deliveries', '"better_supabase"."notification_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_delivery_events', '"better_supabase"."notification_delivery_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_digests', '"better_supabase"."notification_digests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_billed_periods', '"better_supabase"."usage_billed_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drive_grants', '"better_supabase"."drive_drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_node_texts', '"better_supabase"."drive_node_texts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_document_types', '"better_supabase"."attachment_document_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.data_subject_requests', '"better_supabase"."data_subject_requests"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.sso_domains', '"better_supabase"."sso_domains"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sso_providers', '"better_supabase"."sso_providers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_steps', '"better_supabase"."enrollment_steps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invite_codes', '"better_supabase"."invite_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.streams', '"better_supabase"."streams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_credentials', '"better_supabase"."workflow_credentials"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.chat_installations', '"better_supabase"."chat_installations"', 'tenant_id', false, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.inboxes', '"better_supabase"."inboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_teams', '"better_supabase"."inbox_teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversation_events', '"better_supabase"."inbox_conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_deliveries', '"better_supabase"."inbox_message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_inbound_events', '"better_supabase"."inbox_inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.inbox_message_templates', '"better_supabase"."inbox_message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'tenant_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collections', '"better_supabase"."knowledge_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agents', '"better_supabase"."agents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_cache_entries', '"better_supabase"."ai_cache_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_batch_items', '"better_supabase"."ai_batch_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.number_sequences', '"better_supabase"."number_sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, array['token_hash', 'password_hash']::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_records', '"better_supabase"."import_records"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shared_views', '"better_supabase"."shared_views"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.relations', '"better_supabase"."relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.products', '"better_supabase"."products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_options', '"better_supabase"."product_options"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_option_values', '"better_supabase"."product_option_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variants', '"better_supabase"."product_variants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_values', '"better_supabase"."product_variant_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_price_lists', '"better_supabase"."catalog_price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_categories', '"better_supabase"."catalog_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_storefronts', '"better_supabase"."catalog_storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_identifiers', '"better_supabase"."product_identifiers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_relations', '"better_supabase"."product_relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_items', '"better_supabase"."supplier_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_item_mappings', '"better_supabase"."supplier_item_mappings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_groups', '"better_supabase"."discount_groups"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_group_parties', '"better_supabase"."discount_group_parties"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_rules', '"better_supabase"."discount_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_event_alarms', '"better_supabase"."calendar_event_alarms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reaction_scores', '"better_supabase"."reaction_scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_items', '"better_supabase"."approval_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_transactions', '"better_supabase"."ledger_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_entries', '"better_supabase"."ledger_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_balances', '"better_supabase"."ledger_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_holds', '"better_supabase"."ledger_holds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_locations', '"better_supabase"."inventory_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_levels', '"better_supabase"."stock_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_reservations', '"better_supabase"."stock_reservations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfers', '"better_supabase"."stock_transfers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfer_lines', '"better_supabase"."stock_transfer_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_orders', '"better_supabase"."purchase_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_order_lines', '"better_supabase"."purchase_order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisitions', '"better_supabase"."purchase_requisitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisition_lines', '"better_supabase"."purchase_requisition_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipts', '"better_supabase"."inventory_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipt_lines', '"better_supabase"."inventory_receipt_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_counts', '"better_supabase"."stock_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_count_lines', '"better_supabase"."stock_count_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_shipping_rates', '"better_supabase"."order_shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillments', '"better_supabase"."order_fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillment_lines', '"better_supabase"."order_fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_returns', '"better_supabase"."order_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_return_lines', '"better_supabase"."order_return_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_refunds', '"better_supabase"."order_refunds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotions', '"better_supabase"."promotions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_codes', '"better_supabase"."promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_promotion_codes', '"better_supabase"."cart_promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_redemptions', '"better_supabase"."promotion_redemptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forms', '"better_supabase"."forms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_answer_keys', '"better_supabase"."form_answer_keys"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signatures', '"better_supabase"."signatures"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedule_runs', '"better_supabase"."template_schedule_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_kinds', '"better_supabase"."case_kinds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cases', '"better_supabase"."cases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_actions', '"better_supabase"."case_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.job_openings', '"better_supabase"."job_openings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipelines', '"better_supabase"."pipelines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stages', '"better_supabase"."pipeline_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_transitions', '"better_supabase"."pipeline_transitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.companies', '"better_supabase"."companies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.people', '"better_supabase"."people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.company_people', '"better_supabase"."company_people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_terms', '"better_supabase"."payment_terms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_delivery_preferences', '"better_supabase"."document_delivery_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_identities', '"better_supabase"."person_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activities', '"better_supabase"."activities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_levels', '"better_supabase"."invoice_dunning_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_runs', '"better_supabase"."invoice_dunning_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_run_items', '"better_supabase"."invoice_dunning_run_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_history', '"better_supabase"."invoice_dunning_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_allocations', '"better_supabase"."invoice_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_line_sources', '"better_supabase"."invoice_line_sources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approval_levels', '"better_supabase"."invoice_approval_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approvals', '"better_supabase"."invoice_approvals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.e_invoice_endpoints', '"better_supabase"."e_invoice_endpoints"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.e_invoice_deliveries', '"better_supabase"."e_invoice_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_escalations', '"better_supabase"."sla_escalations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.goals', '"better_supabase"."goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_statements', '"better_supabase"."moderation_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automations', '"better_supabase"."automations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_versions', '"better_supabase"."automation_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_evaluations', '"better_supabase"."automation_evaluations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_depreciations', '"better_supabase"."asset_depreciations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leases', '"better_supabase"."leases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_charges', '"better_supabase"."lease_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_categories', '"better_supabase"."expense_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_lines', '"better_supabase"."expense_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_funds', '"better_supabase"."donation_funds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pledges', '"better_supabase"."pledges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_receipts', '"better_supabase"."donation_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donations', '"better_supabase"."donations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_route_stops', '"better_supabase"."dispatch_route_stops"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipments', '"better_supabase"."shipments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_packages', '"better_supabase"."shipment_packages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_tracking_events', '"better_supabase"."shipment_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_lines', '"better_supabase"."shipment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.intrastat_lines', '"better_supabase"."intrastat_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.compliance_policies', '"better_supabase"."compliance_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_components', '"better_supabase"."incident_status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_component_history', '"better_supabase"."incident_status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortem_actions', '"better_supabase"."incident_postmortem_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_regulatory_profiles', '"better_supabase"."incident_regulatory_profiles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_regulatory_filings', '"better_supabase"."incident_regulatory_filings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_pages', '"better_supabase"."incident_status_pages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.courses', '"better_supabase"."courses"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_modules', '"better_supabase"."course_modules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lessons', '"better_supabase"."course_lessons"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.messages', '"better_supabase"."messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_record_mentions', '"better_supabase"."message_record_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_summaries', '"better_supabase"."thread_summaries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.channels', '"better_supabase"."channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timeline_entries', '"better_supabase"."timeline_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.mail_threads', '"better_supabase"."mail_threads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_messages', '"better_supabase"."mail_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracked_links', '"better_supabase"."mail_tracked_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracking_events', '"better_supabase"."mail_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_thread_subjects', '"better_supabase"."mail_thread_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segments', '"better_supabase"."segments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segment_members', '"better_supabase"."segment_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queues', '"better_supabase"."assignment_queues"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignments', '"better_supabase"."assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrichments', '"better_supabase"."enrichments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshots', '"better_supabase"."forecast_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshot_deals', '"better_supabase"."forecast_snapshot_deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_changes', '"better_supabase"."field_changes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequences', '"better_supabase"."sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lead_score_checks', '"better_supabase"."lead_score_checks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.posts', '"better_supabase"."posts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_types', '"better_supabase"."qualification_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_requirements', '"better_supabase"."qualification_requirements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualifications', '"better_supabase"."qualifications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_matrices', '"better_supabase"."risk_matrices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risks', '"better_supabase"."risks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_templates', '"better_supabase"."shift_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shifts', '"better_supabase"."shifts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_codes', '"better_supabase"."tax_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_rates', '"better_supabase"."tax_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_tax_lines', '"better_supabase"."invoice_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_returns', '"better_supabase"."tax_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eu_sales_list_lines', '"better_supabase"."eu_sales_list_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_recognition_schedules', '"better_supabase"."accounting_recognition_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_recognition_rows', '"better_supabase"."accounting_recognition_rows"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_settings', '"better_supabase"."accounting_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_accounts', '"better_supabase"."accounting_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_account_roles', '"better_supabase"."accounting_account_roles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_journals', '"better_supabase"."accounting_journals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_periods', '"better_supabase"."accounting_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entries', '"better_supabase"."accounting_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entry_lines', '"better_supabase"."accounting_entry_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimensions', '"better_supabase"."accounting_dimensions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimension_values', '"better_supabase"."accounting_dimension_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_fx_rates', '"better_supabase"."accounting_fx_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_opening_balances', '"better_supabase"."accounting_opening_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budgets', '"better_supabase"."accounting_budgets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budget_lines', '"better_supabase"."accounting_budget_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_assignments', '"better_supabase"."acknowledgement_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_purposes', '"better_supabase"."consent_purposes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consents', '"better_supabase"."consents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_signals', '"better_supabase"."consent_signals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_receipts', '"better_supabase"."consent_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observation_definitions', '"better_supabase"."observation_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observations', '"better_supabase"."observations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medications', '"better_supabase"."medications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_orders', '"better_supabase"."medication_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_administrations', '"better_supabase"."medication_administrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plans', '"better_supabase"."care_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_problems', '"better_supabase"."care_plan_problems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_goals', '"better_supabase"."care_plan_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_actions', '"better_supabase"."care_plan_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_programs', '"better_supabase"."inspection_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspections', '"better_supabase"."inspections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_findings', '"better_supabase"."inspection_findings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.boms', '"better_supabase"."boms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_centers', '"better_supabase"."work_centers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_operations', '"better_supabase"."bom_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_components', '"better_supabase"."bom_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_orders', '"better_supabase"."production_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_order_operations', '"better_supabase"."production_order_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_consumptions', '"better_supabase"."production_consumptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lot_links', '"better_supabase"."stock_lot_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_accounts', '"better_supabase"."bank_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_rules', '"better_supabase"."bank_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_statements', '"better_supabase"."bank_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_transactions', '"better_supabase"."bank_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_matches', '"better_supabase"."bank_matches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batches', '"better_supabase"."payment_batches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batch_items', '"better_supabase"."payment_batch_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meetings', '"better_supabase"."meetings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_agenda_items', '"better_supabase"."meeting_agenda_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_decisions', '"better_supabase"."meeting_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_action_items', '"better_supabase"."meeting_action_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entities', '"better_supabase"."legal_entities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entity_settings', '"better_supabase"."legal_entity_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_products', '"better_supabase"."funding_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_awards', '"better_supabase"."funding_awards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_deliveries', '"better_supabase"."funding_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claims', '"better_supabase"."funding_claims"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claim_lines', '"better_supabase"."funding_claim_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_runs', '"better_supabase"."payroll_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plans', '"better_supabase"."maintenance_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plan_parts', '"better_supabase"."maintenance_plan_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meters', '"better_supabase"."maintenance_meters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_renditions', '"better_supabase"."dam_renditions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_templates', '"better_supabase"."document_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_text_blocks', '"better_supabase"."document_text_blocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rendered_documents', '"better_supabase"."rendered_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_methods', '"better_supabase"."lims_methods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_competencies', '"better_supabase"."appraisal_competencies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_review_ratings', '"better_supabase"."appraisal_review_ratings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_goals', '"better_supabase"."appraisal_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lines', '"better_supabase"."pick_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.count_plans', '"better_supabase"."count_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.putaway_rules', '"better_supabase"."putaway_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bin_slots', '"better_supabase"."bin_slots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.variant_sizes', '"better_supabase"."variant_sizes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_lines', '"better_supabase"."rfq_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_suppliers', '"better_supabase"."rfq_suppliers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quote_lines', '"better_supabase"."rfq_quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tills', '"better_supabase"."tills"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_rules', '"better_supabase"."care_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.periods', '"better_supabase"."periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deadlines', '"better_supabase"."deadlines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_plans', '"better_supabase"."commission_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_assignments', '"better_supabase"."commission_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commissions', '"better_supabase"."commissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_statements', '"better_supabase"."commission_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.referral_codes', '"better_supabase"."referral_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.referrals', '"better_supabase"."referrals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.e_invoice_endpoints (
  invoice uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_seller jsonb;
  v_buyer jsonb;
begin
  select * into v_row from "better_supabase"."invoices" x where x."id" = e_invoice_endpoints.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false));
  if v_row."id" is null then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  select coalesce(
    (select jsonb_build_object('scheme', e."scheme", 'id', e."endpoint_id") from "better_supabase"."e_invoice_endpoints" e where e."tenant_id" = v_row."tenant_id" and e."party_kind" = 'legal_entity' and e."party_id" = v_row.legal_entity_id::text),
    (select jsonb_build_object('scheme', e."scheme", 'id', e."endpoint_id") from "better_supabase"."e_invoice_endpoints" e where e."tenant_id" = v_row."tenant_id" and e."party_kind" = 'organization' and e."party_id" = v_row."tenant_id"::text)
  ) into v_seller;
  select jsonb_build_object('scheme', e."scheme", 'id', e."endpoint_id") into v_buyer from "better_supabase"."e_invoice_endpoints" e
  where e."tenant_id" = v_row."tenant_id" and e."party_kind" = 'company' and e."party_id" = v_row."company_id"::text;
  return jsonb_build_object('seller', v_seller, 'buyer', v_buyer);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.find_e_endpoint_party (
  tenant      uuid,
  scheme      text,
  endpoint_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', find_e_endpoint_party.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('partyKind', e."party_kind", 'partyId', e."party_id")
    from "better_supabase"."e_invoice_endpoints" e
    where e."tenant_id" = find_e_endpoint_party.tenant
      and e."scheme" = find_e_endpoint_party.scheme
      and lower(e."endpoint_id") = lower(find_e_endpoint_party.endpoint_id)
    order by case e."party_kind" when 'company' then 0 else 1 end, e."created_at"
    limit 1
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_streams (
  older_than interval DEFAULT '1 day'::interval,
  batch      integer  DEFAULT 1000
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_count integer;
begin
  with doomed as (
    select "id" from "better_supabase"."streams"
    where "expires_at" <= now()
      or "closed_at" <= now() - coalesce(older_than, interval '1 day')
    limit greatest(coalesce(batch, 1000), 1)
  )
  delete from "better_supabase"."streams" st using doomed where st."id" = doomed."id";
  get diagnostics v_count = row_count;
  delete from "better_supabase"."stream_entries" where "expires_at" <= now();
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_invoice_e_endpoint (
  tenant      uuid,
  party_kind  text,
  party_id    text,
  scheme      text DEFAULT NULL::text,
  endpoint_id text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."e_invoice_endpoints";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', set_invoice_e_endpoint.tenant, 'invoices.manage'), false)) then
    raise exception 'not allowed to manage invoices in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if set_invoice_e_endpoint.party_kind not in ('organization', 'legal_entity', 'company')
    or nullif(trim(set_invoice_e_endpoint.party_id), '') is null
    or length(set_invoice_e_endpoint.party_id) > 150 then
    raise exception 'party_kind is organization, legal_entity or company, and party_id is a non-empty text of at most 150 characters' using errcode = '22023', hint = 'E_INVOICE_ENDPOINT_INVALID';
  end if;
  if set_invoice_e_endpoint.scheme is null and set_invoice_e_endpoint.endpoint_id is null then
    delete from "better_supabase"."e_invoice_endpoints" x
    where x."tenant_id" = set_invoice_e_endpoint.tenant
      and x."party_kind" = set_invoice_e_endpoint.party_kind
      and x."party_id" = set_invoice_e_endpoint.party_id;
    return null;
  end if;
  if set_invoice_e_endpoint.scheme !~ '^[0-9]{4}$'
    or nullif(trim(set_invoice_e_endpoint.endpoint_id), '') is null
    or length(set_invoice_e_endpoint.endpoint_id) > 200 then
    raise exception 'an endpoint is a four-digit EAS scheme and a non-empty id of at most 200 characters' using errcode = '22023', hint = 'E_INVOICE_ENDPOINT_INVALID';
  end if;
  insert into "better_supabase"."e_invoice_endpoints" ("tenant_id", "party_kind", "party_id", "scheme", "endpoint_id")
  values (set_invoice_e_endpoint.tenant, set_invoice_e_endpoint.party_kind, set_invoice_e_endpoint.party_id, set_invoice_e_endpoint.scheme, trim(set_invoice_e_endpoint.endpoint_id))
  on conflict ("tenant_id", "party_kind", "party_id") do update
    set "scheme" = excluded."scheme", "endpoint_id" = excluded."endpoint_id", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('scheme', v_row."scheme", 'id', v_row."endpoint_id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stream_kv_get (
  key text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select k."value" from "better_supabase"."stream_entries" k
  where k."key" = stream_kv_get.key
    and (k."expires_at" is null or k."expires_at" > now());
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stream_kv_incr (
  key text
)
  RETURNS bigint
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_value text;
  v_next bigint;
begin
  delete from "better_supabase"."stream_entries" where "key" = stream_kv_incr.key and "expires_at" <= now();
  insert into "better_supabase"."stream_entries" ("key", "value") values (key, '1')
  on conflict ("key") do nothing
  returning "value" into v_value;
  if found then
    return 1;
  end if;
  select "value" into v_value from "better_supabase"."stream_entries" where "key" = stream_kv_incr.key for update;
  if v_value !~ '^-?[0-9]{1,18}$' then
    raise exception 'ERR value is not an integer or out of range' using errcode = '22023';
  end if;
  v_next := v_value::bigint + 1;
  update "better_supabase"."stream_entries" set "value" = v_next::text where "key" = stream_kv_incr.key;
  return v_next;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stream_kv_set (
  key   text,
  value text,
  ex    integer DEFAULT NULL::integer
)
  RETURNS text
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  insert into "better_supabase"."stream_entries" ("key", "value", "expires_at")
  values (key, value, case when ex is null then null else now() + make_interval(secs => ex) end)
  on conflict ("key") do update
    set "value" = excluded."value", "expires_at" = excluded."expires_at";
  return 'OK';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sync_workflow_steps (
  steps jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  insert into "better_supabase"."workflow_step_templates" ("name", "title", "description", "input_schema", "output_schema", "credential_kind", "operation")
  select e.key, coalesce(e.value ->> 'title', e.key), e.value ->> 'description',
    coalesce(e.value -> 'inputSchema', '{}'::jsonb), coalesce(e.value -> 'outputSchema', '{}'::jsonb), e.value ->> 'credentialKind',
    nullif(e.value ->> 'operation', '')
  from jsonb_each(coalesce(steps, '{}'::jsonb)) e
  on conflict ("name") do update set
    "title" = excluded."title",
    "description" = excluded."description",
    "input_schema" = excluded."input_schema",
    "output_schema" = excluded."output_schema",
    "credential_kind" = excluded."credential_kind",
    "operation" = excluded."operation",
    "updated_at" = now();
  delete from "better_supabase"."workflow_step_templates" x
  where not exists (
    select 1 from jsonb_each(coalesce(steps, '{}'::jsonb)) e where e.key = x."name"
  );
  select count(*) into v_count from "better_supabase"."workflow_step_templates";
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.validate_workflow_graph (
  graph jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_errors text[] := '{}';
  v_nodes jsonb := coalesce(graph -> 'nodes', 'null'::jsonb);
  v_edges jsonb := coalesce(graph -> 'edges', '[]'::jsonb);
  v_node jsonb;
  v_edge jsonb;
  v_ids text[] := '{}';
  v_branching text[] := '{}';
  v_triggers integer := 0;
begin
  if jsonb_typeof(v_nodes) <> 'array' or jsonb_typeof(v_edges) <> 'array' then
    return jsonb_build_array('A graph has a nodes array and an edges array');
  end if;
  for v_node in select value from jsonb_array_elements(v_nodes) loop
    if coalesce(jsonb_typeof(v_node -> 'id'), '') <> 'string' or (v_node ->> 'id') !~ '^[A-Za-z0-9_-]{1,100}$' then
      v_errors := array_append(v_errors, 'Every node has an id of 1 to 100 letters, digits, underscores or hyphens');
      continue;
    end if;
    if (v_node ->> 'id') = any (v_ids) then
      v_errors := array_append(v_errors, format('Node %s appears twice', v_node ->> 'id'));
    end if;
    v_ids := array_append(v_ids, v_node ->> 'id');
    if coalesce(v_node ->> 'kind', '') in ('condition', 'approval') or exists (
      select 1 from "better_supabase"."workflow_node_kinds" x where x."kind" = v_node ->> 'kind' and x."branches"
    ) then
      v_branching := array_append(v_branching, v_node ->> 'id');
    end if;
    if coalesce(v_node ->> 'kind', '') not in ('trigger', 'step', 'sleep', 'approval', 'condition') and not exists (
      select 1 from "better_supabase"."workflow_node_kinds" x where x."kind" = v_node ->> 'kind'
    ) then
      v_errors := array_append(v_errors, format('Node %s has an unknown kind', v_node ->> 'id'));
    elsif v_node ->> 'kind' = 'trigger' then
      v_triggers := v_triggers + 1;
    elsif v_node ->> 'kind' = 'step' and not exists (
      select 1 from "better_supabase"."workflow_step_templates" s where s."name" = v_node ->> 'step'
    ) then
      v_errors := array_append(v_errors, format('Node %s uses step %s, which is not in the step library', v_node ->> 'id', coalesce(v_node ->> 'step', 'null')));
    end if;
  end loop;
  if v_triggers < 1 then
    v_errors := array_append(v_errors, 'A graph has at least one trigger node');
  end if;
  for v_edge in select value from jsonb_array_elements(v_edges) loop
    if not coalesce((v_edge ->> 'source') = any (v_ids), false) or not coalesce((v_edge ->> 'target') = any (v_ids), false) then
      v_errors := array_append(v_errors, format('Edge %s joins a node that does not exist', coalesce(v_edge ->> 'id', '?')));
    elsif v_edge ? 'branch' and not ((v_edge ->> 'source') = any (v_branching)) then
      v_errors := array_append(v_errors, format('Edge %s takes a branch from a node that does not branch', coalesce(v_edge ->> 'id', '?')));
    end if;
  end loop;
  return to_jsonb(v_errors);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_graph_permissions (
  graph jsonb
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(array_agg(distinct x.p order by x.p), '{}'::text[])
  from (
    select coalesce(
      '{}'::jsonb ->> (n.value ->> 'step'),
      (select coalesce('{}'::jsonb ->> s."operation", s."operation")
        from "better_supabase"."workflow_step_templates" s where s."name" = n.value ->> 'step'),
      'workflow_editor.run'
    ) as p
    from jsonb_array_elements(
      case when jsonb_typeof(workflow_graph_permissions.graph -> 'nodes') = 'array'
        then workflow_graph_permissions.graph -> 'nodes' else '[]'::jsonb end
    ) n
    where n.value ->> 'kind' = 'step'
  ) x;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_steps_list()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', x."name",
    'title', x."title",
    'description', x."description",
    'inputSchema', x."input_schema",
    'outputSchema', x."output_schema",
    'credentialKind', x."credential_kind",
    'operation', x."operation",
    'updatedAt', x."updated_at"
  ) order by x."name"), '[]'::jsonb) from "better_supabase"."workflow_step_templates" x;
$function$;

REVOKE ALL ON FUNCTION "api"."e_invoice_endpoints"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."e_invoice_endpoints"(uuid) TO "authenticated", "service_role";
