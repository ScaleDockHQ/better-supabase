SET local check_function_bodies = off;

REVOKE ALL ON TABLE "better_supabase"."ai_harness_sessions" FROM "authenticated";

DROP POLICY "ai_harness_sessions_owner_read" ON "better_supabase"."ai_harness_sessions";

DROP VIEW "better_supabase"."audit_log";

DROP FUNCTION "api"."set_memory_embedding"(uuid, extensions.vector, text);

DROP FUNCTION "better_supabase"."set_memory_embedding"(uuid, extensions.vector, text);

CREATE OR REPLACE FUNCTION api.set_memory_embedding (
  memory_id    uuid,
  embedding    extensions.vector,
  model        text              DEFAULT NULL::text,
  content_hash text              DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_memory_embedding"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.set_memory_embeddings (
  items jsonb,
  model text  DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_memory_embeddings"($1, $2) $function$;

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
  where (y."status" = 'running' and y."started_at" < now() - interval '30 minutes')
     or (y."status" = 'queued' and y."created_at" < now() - interval '30 minutes');
  for v_task in
    select * from "better_supabase"."ai_scheduled_tasks" x
    where x."enabled" and x."next_run_at" <= now()
    order by x."next_run_at"
    limit least(greatest(claim_due_ai_tasks.batch, 1), 500)
    for update skip locked
  loop
    insert into "better_supabase"."ai_task_runs" ("task_id", "organization_id", "user_id", "scheduled_for", "chat_id")
    values (v_task."id", v_task."organization_id", v_task."user_id", v_task."next_run_at", v_task."chat_id")
    returning * into v_run;
    update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = null, "last_run_at" = now() where x."id" = v_task."id";
    perform "better_supabase"."enqueue_job"(queue => 'ai_task_run', payload => jsonb_build_object('run_id', v_run."id"), dedupe_key => 'ai-task:' || v_run."id"::text, dedupe_running => false);
    v_runs := v_runs || jsonb_build_array(jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'organization_id', v_run."organization_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_for', v_run."scheduled_for", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at"));
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'cron', x."cron", 'timezone', x."timezone")), '[]')
  into v_unscheduled
  from "better_supabase"."ai_scheduled_tasks" x where x."enabled" and x."next_run_at" is null;
  return jsonb_build_object('runs', v_runs, 'unscheduled', v_unscheduled);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.dispatch_workflow_deliveries (
  batch integer DEFAULT 20
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_url text;
  v_secret text;
  v_job record;
  v_body jsonb;
  v_t text;
  v_job_header text;
  v_count integer := 0;
  -- pg_net is optional: http_post is looked up, not named, so plpgsql_check
  -- (supabase db lint) passes without the extension.
  v_post regprocedure := pg_catalog.to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)');
begin
  if v_post is null then
    raise exception 'dispatch_workflow_deliveries needs pg_net: create extension pg_net, or deliver with the poll mode';
  end if;
  select ds.decrypted_secret into v_url from vault.decrypted_secrets ds where ds.name = 'workflow_flow_url';
  select ds.decrypted_secret into v_secret from vault.decrypted_secrets ds where ds.name = 'workflow_delivery_secret';
  if v_url is null or v_secret is null then
    raise exception 'Set the Vault secrets workflow_flow_url and workflow_delivery_secret before dispatching' using hint = 'WORKFLOW_DELIVERY_UNCONFIGURED';
  end if;
  for v_job in select * from "better_supabase"."claim_jobs"('workflow_deliveries', 60, greatest(coalesce(batch, 20), 1)) loop
    v_body := coalesce(v_job.message -> 'payload', '{}'::jsonb);
    v_t := floor(extract(epoch from now()))::bigint::text;
    v_job_header := 'workflow_deliveries' || ':' || v_job.id::text || ':' || v_job.attempts::text;
    execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
      using v_url, v_body, jsonb_build_object(
        'content-type', 'application/json',
        'x-bs-job', v_job_header,
        'x-bs-signature', 't=' || v_t || ',v1=' || encode(extensions.hmac(v_t || '.' || v_job_header || '.' || v_body::text, v_secret, 'sha256'), 'hex')
      ), 30000;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_search (
  tenant          uuid,
  query_embedding extensions.vector DEFAULT NULL::extensions.vector,
  query_text      text              DEFAULT NULL::text,
  ns              jsonb             DEFAULT '{}'::jsonb,
  k               integer           DEFAULT 8
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_owner uuid;
  v_rows jsonb;
  v_candidates integer := least(greatest(memory_search.k, 1) * 4, 400);
  v_scan text := current_setting('hnsw.iterative_scan', true);
begin
  v_scope := coalesce(memory_search.ns ->> 'scope', 'user');
  v_agent := (memory_search.ns ->> 'agent_id')::uuid;
  v_chat := (memory_search.ns ->> 'chat_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_search.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_search.tenant, 'ai_chat.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_search.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  with scoped as materialized (
    select x."id" as id from "better_supabase"."memories" x
    where x."organization_id" = memory_search.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."superseded_by" is null and x."kind" = 'archival'
  ),
  vector_hits as materialized (
    select t."id" as id, t."embedding" operator(extensions.<=>) memory_search.query_embedding as distance
    from "better_supabase"."memories" t
    where memory_search.query_embedding is not null and t."embedding" is not null and t."id" in (select scoped.id from scoped)
    order by t."embedding" operator(extensions.<=>) memory_search.query_embedding
    limit v_candidates
  ),
  vector_ranked as (
    select h.id, h.distance, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  text_ranked as (
    select t."id" as id, row_number() over (order by ts_rank_cd(t."tsv", q) desc) as rank
    from "better_supabase"."memories" t, websearch_to_tsquery('simple'::regconfig, memory_search.query_text) q
    where memory_search.query_text is not null and t."tsv" @@ q and t."id" in (select scoped.id from scoped)
    limit v_candidates
  ),
  fused as (
    select coalesce(v.id, x.id) as id, v.distance,
      coalesce(1.0 / (60 + v.rank), 0) + coalesce(1.0 / (60 + x.rank), 0) as score
    from vector_ranked v full join text_ranked x on x.id = v.id
    order by score desc
    limit least(greatest(memory_search.k, 1), 100)
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'organization_id', t."organization_id", 'owner_id', t."owner_id", 'scope', t."scope", 'agent_id', t."agent_id", 'chat_id', t."chat_id", 'kind', t."kind", 'path', t."path", 'content', t."content", 'version', t."version", 'embedding_model', t."embedding_model", 'source_message_id', t."source_message_id", 'created_at', t."created_at", 'updated_at', t."updated_at") || jsonb_build_object('score', f.score, 'similarity', 1 - f.distance) order by f.score desc), '[]')
  into v_rows
  from fused f join "better_supabase"."memories" t on t."id" = f.id;
  perform set_config('hnsw.iterative_scan', coalesce(nullif(v_scan, ''), 'off'), true);
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pending_knowledge_chunks (
  document_id uuid,
  batch       integer DEFAULT 64
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('idx', x."idx", 'content', x."content", 'hash', md5(x."content")) order by x."idx"), '[]')
  from (
    select * from "better_supabase"."knowledge_chunks" y
    where y."document_id" = pending_knowledge_chunks.document_id and y."embedding" is null
    order by y."idx"
    limit least(greatest(pending_knowledge_chunks.batch, 1), 2048)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pending_memory_embeddings (
  batch integer DEFAULT 64
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'content', x."content", 'hash', md5(x."content"))), '[]')
  from (
    select * from "better_supabase"."memories" y where y."embedding" is null and y."superseded_by" is null
    order by y."updated_at"
    limit least(greatest(pending_memory_embeddings.batch, 1), 2048)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_workflow_version (
  version  uuid,
  compiled jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
  v_errors jsonb;
begin
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version for update;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.publish'), false))) then
    raise exception 'You may not publish this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if compiled is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role may store a compiled form' using errcode = '42501', hint = 'WORKFLOW_COMPILED_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    if compiled is not null then
      update "better_supabase"."workflow_versions" x set "compiled" = compiled
      where x."id" = v_row."id"
      returning * into v_row;
    end if;
    return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
  end if;
  v_errors := "better_supabase"."validate_workflow_graph"(v_row."graph");
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  update "better_supabase"."workflow_versions" x set "status" = 'archived'
  where x."definition_id" = v_row."definition_id" and x."status" = 'published';
  update "better_supabase"."workflow_versions" x set "status" = 'published', "compiled" = compiled, "published_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.recall_ai_messages (
  tenant          uuid,
  query_embedding extensions.vector,
  k               integer           DEFAULT 5,
  exclude_chat    uuid              DEFAULT NULL::uuid,
  owner           uuid              DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_user uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then recall_ai_messages.owner else auth.uid() end;
  v_rows jsonb;
  v_scan text := current_setting('hnsw.iterative_scan', true);
begin
  if v_user is null then
    return '[]';
  end if;
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  select coalesce(jsonb_agg(jsonb_build_object('chat_id', r.chat_id, 'message_id', r.message_id, 'similarity', 1 - r.distance) order by r.distance), '[]')
  into v_rows
  from (
    select x."chat_id" as chat_id, x."message_id" as message_id, x."embedding" operator(extensions.<=>) recall_ai_messages.query_embedding as distance
    from "better_supabase"."ai_message_embeddings" x
    where x."user_id" = v_user and x."organization_id" = recall_ai_messages.tenant
      and x."chat_id" is distinct from recall_ai_messages.exclude_chat
    order by x."embedding" operator(extensions.<=>) recall_ai_messages.query_embedding
    limit least(greatest(recall_ai_messages.k, 1), 50)
  ) r;
  perform set_config('hnsw.iterative_scan', coalesce(nullif(v_scan, ''), 'off'), true);
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_harness_session (
  chat    uuid,
  harness text,
  fields  jsonb,
  holder  text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_row "better_supabase"."ai_harness_sessions";
  v_status text := save_ai_harness_session.fields ->> 'status';
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if nullif(save_ai_harness_session.harness, '') is null then
    raise exception 'A harness session needs a harness id' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  if jsonb_typeof(save_ai_harness_session.fields) is distinct from 'object'
    or (v_status is not null and v_status not in ('active', 'idle', 'stopped', 'error')) then
    raise exception 'fields must be an object and status active, idle, stopped or error' using errcode = '22023', hint = 'AI_HARNESS_INVALID';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = save_ai_harness_session.chat;
  if not found then
    raise exception 'No chat %', save_ai_harness_session.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_harness_sessions" ("chat_id", "harness_id", "owner_id")
  values (v_chat."id", save_ai_harness_session.harness, v_chat."owner_id")
  on conflict ("chat_id", "harness_id") do nothing;
  select * into v_row from "better_supabase"."ai_harness_sessions" x
  where x."chat_id" = v_chat."id" and x."harness_id" = save_ai_harness_session.harness
  for update;
  if v_row."locked_until" > now() and v_row."lock_holder" is distinct from save_ai_harness_session.holder then
    raise exception 'Harness session % is locked', save_ai_harness_session.harness using errcode = '55P03', hint = 'AI_HARNESS_LOCKED';
  end if;
  update "better_supabase"."ai_harness_sessions" x set
    "resume_state" = case when save_ai_harness_session.fields ? 'resume_state' then save_ai_harness_session.fields -> 'resume_state' else x."resume_state" end,
    "continue_state" = case when save_ai_harness_session.fields ? 'continue_state' then save_ai_harness_session.fields -> 'continue_state' else x."continue_state" end,
    "sandbox_id" = case when save_ai_harness_session.fields ? 'sandbox_id' then save_ai_harness_session.fields ->> 'sandbox_id' else x."sandbox_id" end,
    -- A save without a status is a turn using the sandbox: an idle session
    -- turns active again, so a later idle_ai_harness_sessions finds it.
    "status" = coalesce(v_status, case when x."status" = 'idle' then 'active' else x."status" end),
    "last_active_at" = now(),
    "updated_at" = now()
  where x."chat_id" = v_row."chat_id" and x."harness_id" = v_row."harness_id"
  returning * into v_row;
  return jsonb_build_object('chat_id', v_row."chat_id", 'harness_id', v_row."harness_id", 'owner_id', v_row."owner_id", 'resume_state', v_row."resume_state", 'continue_state', v_row."continue_state", 'sandbox_id', v_row."sandbox_id", 'status', v_row."status", 'lock_holder', v_row."lock_holder", 'locked_until', v_row."locked_until", 'last_active_at', v_row."last_active_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_provider_key (
  tenant         uuid,
  provider       text,
  credential_ref jsonb,
  name           text    DEFAULT 'default'::text,
  settings       jsonb   DEFAULT '{}'::jsonb,
  enabled        boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old jsonb;
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_provider_key.tenant, 'ai_chat.admin'), false)) then
    raise exception 'you may not manage provider keys here' using errcode = '42501', hint = 'AI_PROVIDER_KEY_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_ai_provider_key.credential_ref is not null and jsonb_typeof(save_ai_provider_key.credential_ref) <> 'null'
    and (jsonb_typeof(save_ai_provider_key.credential_ref -> 'tenant') is distinct from 'string' or (save_ai_provider_key.credential_ref ->> 'tenant') is distinct from (save_ai_provider_key.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_ai_provider_key.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  select x."credential_ref" into v_old from "better_supabase"."ai_provider_keys" x
  where x."organization_id" = save_ai_provider_key.tenant and x."provider" = save_ai_provider_key.provider and x."name" = coalesce(save_ai_provider_key.name, 'default')
  for update;
  insert into "better_supabase"."ai_provider_keys" ("organization_id", "provider", "name", "credential_ref", "settings", "enabled", "created_by")
  values (save_ai_provider_key.tenant, save_ai_provider_key.provider, coalesce(save_ai_provider_key.name, 'default'), save_ai_provider_key.credential_ref, coalesce(save_ai_provider_key.settings, '{}'), coalesce(save_ai_provider_key.enabled, true), auth.uid())
  on conflict ("organization_id", "provider", "name") do update set
    "credential_ref" = excluded."credential_ref",
    "settings" = excluded."settings",
    "enabled" = excluded."enabled",
    "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('key', jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at"), 'replaced', v_old);
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
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_task.tenant, 'ai_chat.create'), false)) or auth.uid() is null then
      raise exception 'you may not schedule tasks here' using errcode = '42501', hint = 'AI_TASK_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_scheduled_tasks" ("organization_id", "user_id", "title", "prompt", "cron")
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id and x."organization_id" = save_ai_task.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
      raise exception 'task % not found', v_id using errcode = 'P0002', hint = 'AI_TASK_NOT_FOUND';
    end if;
  end if;
  v_chat := (save_ai_task.fields ->> 'chat_id')::uuid;
  if v_chat is not null and not v_service and not exists (select 1 from "better_supabase"."ai_chats" c where c."id" = v_chat and c."owner_id" = v_row."user_id" and c."organization_id" = v_row."organization_id")
  then
    raise exception 'chat % is not a chat of this task''s user', v_chat using errcode = '42501', hint = 'AI_TASK_CHAT_FORBIDDEN';
  end if;
  v_agent := (save_ai_task.fields ->> 'agent_id')::uuid;
  if v_agent is not null and not v_service and not exists (select 1 from "better_supabase"."agents" g where g."id" = v_agent and g."organization_id" = v_row."organization_id" and (g."owner_id" = v_row."user_id" or g."published_at" is not null))
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
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'prompt', v_row."prompt", 'cron', v_row."cron", 'timezone', v_row."timezone", 'enabled', v_row."enabled", 'next_run_at', v_row."next_run_at", 'last_run_at', v_row."last_run_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_connector_server (
  tenant uuid,
  id     uuid  DEFAULT NULL::uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'ai_chat.admin'), false)) then
    raise exception 'you may not manage connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  if jsonb_typeof(save_connector_server.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CONNECTOR_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_connector_server.fields -> 'credential_ref' is not null and jsonb_typeof(save_connector_server.fields -> 'credential_ref') <> 'null'
    and (jsonb_typeof(save_connector_server.fields -> 'credential_ref' -> 'tenant') is distinct from 'string' or (save_connector_server.fields -> 'credential_ref' ->> 'tenant') is distinct from (save_connector_server.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_connector_server.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  if save_connector_server.id is null then
    insert into "better_supabase"."connector_servers" ("organization_id", "name", "url", "auth_type", "credential_ref", "created_by")
    values (save_connector_server.tenant, save_connector_server.fields ->> 'name', save_connector_server.fields ->> 'url',
      coalesce(save_connector_server.fields ->> 'auth_type', 'oauth'), save_connector_server.fields -> 'credential_ref', auth.uid())
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."connector_servers" x where x."id" = save_connector_server.id and x."organization_id" = save_connector_server.tenant for update;
    if not found then
      raise exception 'connector % not found', save_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."connector_servers" x set
    "name" = coalesce(save_connector_server.fields ->> 'name', x."name"),
    "url" = coalesce(save_connector_server.fields ->> 'url', x."url"),
    "transport" = coalesce(save_connector_server.fields ->> 'transport', x."transport"),
    "auth_type" = coalesce(save_connector_server.fields ->> 'auth_type', x."auth_type"),
    "credential_ref" = case when save_connector_server.fields ? 'credential_ref' then nullif(save_connector_server.fields -> 'credential_ref', 'null') else x."credential_ref" end,
    "scopes" = case when save_connector_server.fields ? 'scopes' then array(select jsonb_array_elements_text(save_connector_server.fields -> 'scopes')) else x."scopes" end,
    "client_metadata" = coalesce(save_connector_server.fields -> 'client_metadata', x."client_metadata"),
    "enabled" = coalesce((save_connector_server.fields ->> 'enabled')::boolean, x."enabled"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_credential (
  tenant uuid,
  kind   text,
  name   text,
  ref    jsonb,
  scopes text[] DEFAULT '{}'::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_credentials"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
    raise exception 'You may not manage workflow credentials here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and save_workflow_credential.ref is not null and jsonb_typeof(save_workflow_credential.ref) <> 'null'
    and (jsonb_typeof(save_workflow_credential.ref -> 'tenant') is distinct from 'string' or (save_workflow_credential.ref ->> 'tenant') is distinct from (save_workflow_credential.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', save_workflow_credential.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  insert into "better_supabase"."workflow_credentials" as x ("tenant_id", "kind", "name", "credential_ref", "scopes", "created_by")
  values (tenant, kind, name, ref, coalesce(scopes, '{}'), (select auth.uid()))
  on conflict on constraint workflow_credentials_tenant_name_key do update set
    "kind" = excluded."kind",
    "credential_ref" = excluded."credential_ref",
    "scopes" = excluded."scopes"
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'kind', v_row."kind",
    'name', v_row."name",
    'ref', v_row."credential_ref",
    'scopes', to_jsonb(v_row."scopes"),
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
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
  where x."id" = (item ->> 'id')::uuid and x."enabled" and x."next_run_at" is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_knowledge_embeddings (
  document_id uuid,
  embeddings  jsonb,
  model       text  DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_remaining integer;
  v_items jsonb := case when jsonb_typeof(set_knowledge_embeddings.embeddings) = 'object' then set_knowledge_embeddings.embeddings -> 'items' else set_knowledge_embeddings.embeddings end;
begin
  update "better_supabase"."knowledge_chunks" t set
    "embedding" = (e.value ->> 'embedding')::extensions.vector(1536),
    "embedding_hash" = e.value ->> 'hash'
  from jsonb_array_elements(coalesce(v_items, '[]')) e
  where t."document_id" = set_knowledge_embeddings.document_id and t."idx" = (e.value ->> 'idx')::integer
    and md5(t."content") = e.value ->> 'hash';
  select count(*)::integer into v_remaining from "better_supabase"."knowledge_chunks" t
  where t."document_id" = set_knowledge_embeddings.document_id and t."embedding" is null;
  update "better_supabase"."knowledge_documents" x set
    "status" = case when v_remaining = 0 then 'ready' else x."status" end,
    "embedding_model" = coalesce(set_knowledge_embeddings.model, x."embedding_model"),
    "updated_at" = now()
  where x."id" = set_knowledge_embeddings.document_id;
  return v_remaining;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_memory_embedding (
  memory_id    uuid,
  embedding    extensions.vector,
  model        text              DEFAULT NULL::text,
  content_hash text              DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  update "better_supabase"."memories" x set "embedding" = set_memory_embedding.embedding, "embedding_model" = set_memory_embedding.model
  where x."id" = set_memory_embedding.memory_id
    and (set_memory_embedding.content_hash is null or md5(x."content") = set_memory_embedding.content_hash)
  returning true
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_memory_embeddings (
  items jsonb,
  model text  DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_items jsonb := case when jsonb_typeof(set_memory_embeddings.items) = 'object' then set_memory_embeddings.items -> 'items' else set_memory_embeddings.items end;
  v_count integer;
begin
  update "better_supabase"."memories" x set
    "embedding" = (e.value ->> 'embedding')::extensions.vector(1536),
    "embedding_model" = set_memory_embeddings.model
  from jsonb_array_elements(case when jsonb_typeof(v_items) = 'array' then v_items else '[]' end) e
  where x."id" = (e.value ->> 'id')::uuid and md5(x."content") = e.value ->> 'hash';
  get diagnostics v_count = row_count;
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
    if coalesce(v_node ->> 'kind', '') not in ('trigger', 'step', 'sleep', 'approval', 'condition') then
      v_errors := array_append(v_errors, format('Node %s has an unknown kind', v_node ->> 'id'));
    elsif v_node ->> 'kind' = 'trigger' then
      v_triggers := v_triggers + 1;
    elsif v_node ->> 'kind' = 'step' and not exists (
      select 1 from "better_supabase"."workflow_step_library" s where s."name" = v_node ->> 'step'
    ) then
      v_errors := array_append(v_errors, format('Node %s uses step %s, which is not in the step library', v_node ->> 'id', coalesce(v_node ->> 'step', 'null')));
    end if;
  end loop;
  if v_triggers <> 1 then
    v_errors := array_append(v_errors, 'A graph has exactly one trigger node');
  end if;
  for v_edge in select value from jsonb_array_elements(v_edges) loop
    if not coalesce((v_edge ->> 'source') = any (v_ids), false) or not coalesce((v_edge ->> 'target') = any (v_ids), false) then
      v_errors := array_append(v_errors, format('Edge %s joins a node that does not exist', coalesce(v_edge ->> 'id', '?')));
    end if;
  end loop;
  return to_jsonb(v_errors);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_sdk_mirror_run()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_actor uuid;
begin
  begin
    v_tenant := (new.attributes ->> 'bs.tenant')::uuid;
  exception when others then
    v_tenant := null;
  end;
  begin
    v_actor := (new.attributes ->> 'bs.actor')::uuid;
  exception when others then
    v_actor := null;
  end;
  if v_tenant is not null and v_actor is not null
    and not coalesce(better_supabase.can_user(v_actor, 'tenant', v_tenant, 'workflow.run'), false) then
    v_tenant := null;
  end if;
  perform "better_supabase"."record_workflow_run"(
    'workflow-sdk',
    new.id,
    new.name,
    case new.status::text when 'pending' then 'queued' else new.status::text end,
    v_tenant,
    v_actor,
    coalesce(new.attributes, '{}'::jsonb) - 'bs.tenant' - 'bs.actor',
    case when new.status::text = 'failed' then coalesce(new.error_code, left(new.error, 4000)) end,
    new.started_at at time zone 'UTC',
    new.completed_at at time zone 'UTC'
  );
  return null;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."set_memory_embedding"(uuid, extensions.vector, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_memory_embedding"(uuid, extensions.vector, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_memory_embeddings"(jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_memory_embeddings"(jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_memory_embedding"(uuid, extensions.vector, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_memory_embedding"(uuid, extensions.vector, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_memory_embeddings"(jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_memory_embeddings"(jsonb, text) TO "service_role";
