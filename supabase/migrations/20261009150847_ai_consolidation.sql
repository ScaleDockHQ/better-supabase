SET local check_function_bodies = off;

DROP POLICY "agents_read" ON "better_supabase"."agents";

DROP POLICY "ai_batches_read" ON "better_supabase"."ai_batches";

DROP POLICY "ai_documents_read" ON "better_supabase"."ai_documents";

DROP POLICY "ai_files_read" ON "better_supabase"."ai_files";

DROP POLICY "ai_provider_keys_read" ON "better_supabase"."ai_provider_keys";

DROP POLICY "ai_scheduled_tasks_read" ON "better_supabase"."ai_scheduled_tasks";

DROP POLICY "ai_task_runs_read" ON "better_supabase"."ai_task_runs";

DROP POLICY "connector_servers_read" ON "better_supabase"."connector_servers";

DROP POLICY "knowledge_documents_read" ON "better_supabase"."knowledge_documents";

DROP POLICY "memories_read" ON "better_supabase"."memories";

DROP FUNCTION "api"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint);

DROP FUNCTION "better_supabase"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint);

CREATE OR REPLACE FUNCTION api.release_ai_chat_stream (
  chat           uuid,
  stream         text,
  status         text   DEFAULT 'completed'::text,
  usage          jsonb  DEFAULT NULL::jsonb,
  generation_id  text   DEFAULT NULL::text,
  error          text   DEFAULT NULL::text,
  cost_micro_usd bigint DEFAULT NULL::bigint
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."release_ai_chat_stream"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_file_object_allowed (
  bucket text,
  path   text,
  action text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."ai_files" a
    where a."bucket" = ai_file_object_allowed.bucket and a."path" = ai_file_object_allowed.path
      and case ai_file_object_allowed.action
        when 'insert' then a."status" = 'pending' and a."owner_id" = auth.uid()
        when 'select' then a."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'ai.admin'), false) or (a."chat_id" is not null and "better_supabase"."ai_chat_can_read"(a."chat_id"))
        when 'delete' then a."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', a."organization_id", 'ai.admin'), false)
        else false
      end
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_sandbox_for (
  chat_id  uuid,
  provider text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'harness_id', x."harness_id", 'provider', x."provider", 'sandbox_id', x."sandbox_id", 'container_id', x."container_id", 'status', x."status", 'metadata', x."metadata", 'idle_seconds', x."idle_seconds", 'error', x."error", 'last_used_at', x."last_used_at", 'expires_at', x."expires_at", 'stopped_at', x."stopped_at", 'created_at', x."created_at", 'updated_at', x."updated_at") from "better_supabase"."ai_sandboxes" x
  where x."chat_id" = ai_sandbox_for.chat_id and x."provider" = ai_sandbox_for.provider and x."status" = 'running'
    and (x."expires_at" is null or x."expires_at" > now())
  order by x."last_used_at" desc
  limit 1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_connector_fingerprint (
  server_id   uuid,
  fingerprint text,
  tools       jsonb DEFAULT '{}'::jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_status text;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = check_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.create'), false)) then
    raise exception 'connector % not found', check_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select p."status" into v_status from "better_supabase"."connector_tool_fingerprints" p
  where p."server_id" = v_server."id" and p."fingerprint" = check_connector_fingerprint.fingerprint;
  if found then
    return v_status;
  end if;
  v_status := case when exists (select 1 from "better_supabase"."connector_tool_fingerprints" p where p."server_id" = v_server."id") then 'pending' else 'approved' end;
  insert into "better_supabase"."connector_tool_fingerprints" ("server_id", "fingerprint", "tools", "status", "approved_at")
  values (v_server."id", check_connector_fingerprint.fingerprint, coalesce(check_connector_fingerprint.tools, '{}'), v_status,
    case when v_status = 'approved' then now() end)
  on conflict do nothing;
  return v_status;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_ai_chat_stream (
  chat            uuid,
  stream          text,
  model           text DEFAULT NULL::text,
  message_id      text DEFAULT NULL::text,
  engine          text DEFAULT 'ai-sdk'::text,
  external_run_id text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_run "better_supabase"."ai_runs";
  v_run_id uuid;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = claim_ai_chat_stream.chat for update;
  if not found then
    raise exception 'No chat %', claim_ai_chat_stream.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if v_chat."active_stream_id" is not null then
    select * into v_run from "better_supabase"."ai_runs" x where x."id" = v_chat."active_run_id";
    if v_chat."active_stream_id" = claim_ai_chat_stream.stream then
      return jsonb_build_object('claimed', true, 'stream_id', v_chat."active_stream_id", 'run_id', v_chat."active_run_id");
    end if;
    if v_run."id" is not null
      and v_run."status" in ('queued', 'running', 'cancel_requested')
      and v_run."started_at" > now() - interval '10 minutes'
      and not exists (
        select 1 from "better_supabase"."streams" so
        where so."id" = v_chat."active_stream_id" and so."closed_at" is not null
      ) then
      return jsonb_build_object('claimed', false, 'stream_id', v_chat."active_stream_id", 'run_id', v_chat."active_run_id");
    end if;
    update "better_supabase"."ai_runs" x set "status" = 'cancelled', "ended_at" = now()
    where x."id" = v_chat."active_run_id" and x."ended_at" is null;
  end if;
  insert into "better_supabase"."ai_runs" ("chat_id", "owner_id", "assistant_message_id", "stream_id", "engine", "external_run_id", "model")
  values (v_chat."id", v_chat."owner_id", claim_ai_chat_stream.message_id, claim_ai_chat_stream.stream, coalesce(claim_ai_chat_stream.engine, 'ai-sdk'), claim_ai_chat_stream.external_run_id, coalesce(claim_ai_chat_stream.model, v_chat."model"))
  returning "id" into v_run_id;
  update "better_supabase"."ai_chats" x set "active_stream_id" = claim_ai_chat_stream.stream, "active_run_id" = v_run_id, "updated_at" = now()
  where x."id" = v_chat."id";
  perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'stream.started', jsonb_build_object('streamId', claim_ai_chat_stream.stream, 'runId', v_run_id), false);
  return jsonb_build_object('claimed', true, 'stream_id', claim_ai_chat_stream.stream, 'run_id', v_run_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_ai_document (
  tenant       uuid,
  kind         text,
  title        text,
  content      text DEFAULT NULL::text,
  chat_id      uuid DEFAULT NULL::uuid,
  message_id   text DEFAULT NULL::text,
  owner        uuid DEFAULT NULL::uuid,
  storage_path text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_owner uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then create_ai_document.owner else auth.uid() end;
  v_row "better_supabase"."ai_documents"%rowtype;
begin
  if v_owner is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_ai_document.tenant, 'ai.create'), false)) then
    raise exception 'you may not create documents here' using errcode = '42501', hint = 'AI_DOCUMENT_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_documents" ("organization_id", "owner_id", "chat_id", "kind", "title")
  values (create_ai_document.tenant, v_owner, create_ai_document.chat_id, create_ai_document.kind, create_ai_document.title)
  returning * into v_row;
  insert into "better_supabase"."ai_document_versions" ("document_id", "version", "content", "storage_path", "created_by_message_id", "created_by")
  values (v_row."id", 1, create_ai_document.content, create_ai_document.storage_path, create_ai_document.message_id, v_owner);
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'title', v_row."title", 'current_version', v_row."current_version", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_knowledge_document (
  tenant   uuid,
  title    text,
  scope    text  DEFAULT 'user'::text,
  scope_id uuid  DEFAULT NULL::uuid,
  file_id  uuid  DEFAULT NULL::uuid,
  source   text  DEFAULT NULL::text,
  metadata jsonb DEFAULT '{}'::jsonb,
  owner    uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_owner uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then create_knowledge_document.owner else auth.uid() end;
  v_scope_id uuid := create_knowledge_document.scope_id;
  v_row "better_supabase"."knowledge_documents"%rowtype;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ai.create'), false)) then
    raise exception 'you may not add knowledge here' using errcode = '42501', hint = 'KNOWLEDGE_FORBIDDEN';
  end if;
  if create_knowledge_document.scope in ('organization', 'agent') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ai.admin'), false)) then
    raise exception 'only admins add % knowledge', create_knowledge_document.scope using errcode = '42501', hint = 'KNOWLEDGE_FORBIDDEN';
  end if;
  if create_knowledge_document.scope = 'user' then
    v_scope_id := coalesce(v_scope_id, v_owner);
    if v_scope_id is null or v_scope_id is distinct from v_owner then
      raise exception 'user knowledge belongs to its owner' using errcode = '22023', hint = 'KNOWLEDGE_SCOPE';
    end if;
  end if;
  if create_knowledge_document.scope is null
    or create_knowledge_document.scope not in ('organization', 'agent', 'project', 'chat', 'user')
    or (create_knowledge_document.scope = 'organization') <> (v_scope_id is null) then
    raise exception '% knowledge needs %', create_knowledge_document.scope, case when create_knowledge_document.scope = 'organization' then 'no scope_id' else 'a scope_id' end using errcode = '22023', hint = 'KNOWLEDGE_SCOPE';
  end if;
  if create_knowledge_document.scope = 'chat' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_scope_id is not null and "better_supabase"."ai_chat_can_read"(v_scope_id))) then
    raise exception 'chat % not found', v_scope_id using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if file_id is not null and not exists (
    select 1 from "better_supabase"."ai_files" x
    where x."id" = create_knowledge_document.file_id
      and x."organization_id" = create_knowledge_document.tenant
      and x."status" = 'ready'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', create_knowledge_document.tenant, 'ai.admin'), false))
  ) then
    raise exception 'file % not found', file_id using errcode = 'P0002', hint = 'AI_FILE_NOT_FOUND';
  end if;
  insert into "better_supabase"."knowledge_documents" ("organization_id", "owner_id", "scope", "scope_id", "file_id", "title", "source", "metadata")
  values (create_knowledge_document.tenant, v_owner, create_knowledge_document.scope, v_scope_id, create_knowledge_document.file_id, create_knowledge_document.title, create_knowledge_document.source, coalesce(create_knowledge_document.metadata, '{}'))
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'scope_id', v_row."scope_id", 'file_id', v_row."file_id", 'title', v_row."title", 'source', v_row."source", 'metadata', v_row."metadata", 'status', v_row."status", 'error', v_row."error", 'chunk_count', v_row."chunk_count", 'embedding_model', v_row."embedding_model", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_connector_fingerprint (
  server_id   uuid,
  fingerprint text,
  approved    boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = decide_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', decide_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  update "better_supabase"."connector_tool_fingerprints" p set
    "status" = case when decide_connector_fingerprint.approved then 'approved' else 'rejected' end,
    "approved_by" = auth.uid(), "approved_at" = now()
  where p."server_id" = v_server."id" and p."fingerprint" = decide_connector_fingerprint.fingerprint;
  if not found then
    return false;
  end if;
  perform better_supabase.audit_event(
    event_type => 'connector.fingerprint_decided',
    category => 'integration',
    target_type => 'connector',
    record_id => v_server."id"::text,
    target_label => v_server."name",
    tenant => (v_server."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_server."organization_id"::text, 'serverId', v_server."id", 'name', v_server."name", 'fingerprint', decide_connector_fingerprint.fingerprint, 'approved', decide_connector_fingerprint.approved)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_agent (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  select * into v_row from "better_supabase"."agents" x where x."id" = delete_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.moderate'), false)) then
    return false;
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  perform better_supabase.audit_event(
    event_type => 'agent.deleted',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_document (
  document_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_documents"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_documents" x where x."id" = delete_ai_document.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_documents" x where x."id" = v_row."id";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_file (
  file_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_files"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_files" x where x."id" = delete_ai_file.file_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    return null;
  end if;
  delete from "better_supabase"."ai_files" x where x."id" = v_row."id";
  return jsonb_build_object('bucket', v_row."bucket", 'path', v_row."path");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_provider_key (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_provider_keys"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_provider_keys" x where x."id" = delete_ai_provider_key.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    return null;
  end if;
  delete from "better_supabase"."ai_provider_keys" x where x."id" = v_row."id";
  perform better_supabase.audit_event(
    event_type => 'ai_provider_key.deleted',
    category => 'security',
    target_type => 'ai_provider_key',
    record_id => v_row."id"::text,
    target_label => v_row."provider" || '/' || v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'keyId', v_row."id", 'provider', v_row."provider", 'name', v_row."name")
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'provider', v_row."provider", 'name', v_row."name", 'credential_ref', v_row."credential_ref", 'settings', v_row."settings", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_task (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := delete_ai_task.id;
  v_row "better_supabase"."ai_scheduled_tasks"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_connector_server (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
  v_grants jsonb;
begin
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = delete_connector_server.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'connector % not found', delete_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at")), '[]') into v_grants
  from "better_supabase"."connector_grants" y where y."server_id" = v_row."id" and y."revoked_at" is null;
  delete from "better_supabase"."connector_servers" x where x."id" = v_row."id";
  perform better_supabase.audit_event(
    event_type => 'connector.deleted',
    category => 'integration',
    target_type => 'connector',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name")
  );
  return v_grants;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_knowledge_document (
  document_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."knowledge_documents"%rowtype;
begin
  select * into v_row from "better_supabase"."knowledge_documents" x where x."id" = delete_knowledge_document.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."knowledge_documents" x where x."id" = v_row."id";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finish_ai_sandbox_stop (
  id      uuid,
  stopped boolean,
  error   text    DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_sandboxes"%rowtype;
begin
  update "better_supabase"."ai_sandboxes" x set
    "status" = case when finish_ai_sandbox_stop.stopped then 'stopped' else 'running' end,
    "stopped_at" = case when finish_ai_sandbox_stop.stopped then now() else null end,
    "error" = left(finish_ai_sandbox_stop.error, 4000),
    "updated_at" = now()
  where x."id" = finish_ai_sandbox_stop.id and x."status" = 'stopping'
  returning x.* into v_row;
  if not found then
    return false;
  end if;
  if finish_ai_sandbox_stop.stopped and v_row."harness_id" is not null then
    update "better_supabase"."ai_harness_sessions" z set "status" = 'stopped', "updated_at" = now()
    where z."chat_id" = v_row."chat_id" and z."harness_id" = v_row."harness_id"
      and z."status" in ('active', 'idle')
      and not exists (
        select 1 from "better_supabase"."ai_sandboxes" y
        where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped'
      );
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finish_ai_task_run (
  id        uuid,
  succeeded boolean,
  error     text    DEFAULT NULL::text,
  chat_id   uuid    DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_task uuid;
begin
  update "better_supabase"."ai_task_runs" y set
    "status" = case when finish_ai_task_run.succeeded then 'completed' else 'failed' end,
    "error" = left(finish_ai_task_run.error, 4000),
    "chat_id" = coalesce(finish_ai_task_run.chat_id, y."chat_id"),
    "finished_at" = now()
  where y."id" = finish_ai_task_run.id and y."status" = 'running'
  returning y."task_id" into v_task;
  if not found then
    return false;
  end if;
  if finish_ai_task_run.chat_id is not null then
    update "better_supabase"."ai_scheduled_tasks" x set "chat_id" = finish_ai_task_run.chat_id where x."id" = v_task and x."chat_id" is null;
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_connector (
  id    uuid,
  owner uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_user uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then get_connector.owner else auth.uid() end;
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = get_connector.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = v_row."id" and y."user_id" = v_user and y."revoked_at" is null
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.idle_ai_harness_sessions (
  idle_seconds integer DEFAULT 900,
  size         integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_result jsonb;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  with picked as (
    select x."chat_id", x."harness_id" from "better_supabase"."ai_harness_sessions" x
    where x."status" = 'active'
      and exists (
        select 1 from "better_supabase"."ai_sandboxes" y
        where y."chat_id" = x."chat_id" and y."harness_id" = x."harness_id" and y."status" = 'running'
      )
      and x."last_active_at" < now() - make_interval(secs => greatest(coalesce(idle_ai_harness_sessions.idle_seconds, 900), 1))
      and (x."locked_until" is null or x."locked_until" <= now())
    order by x."last_active_at"
    limit least(greatest(coalesce(idle_ai_harness_sessions.size, 100), 1), 1000)
    for update skip locked
  ), marked as (
    update "better_supabase"."ai_harness_sessions" x set "status" = 'idle', "updated_at" = now()
    from picked
    where x."chat_id" = picked."chat_id" and x."harness_id" = picked."harness_id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('chat_id', marked."chat_id", 'harness_id', marked."harness_id", 'owner_id', marked."owner_id", 'resume_state', marked."resume_state", 'continue_state', marked."continue_state", 'sandbox_id', (select y."sandbox_id" from "better_supabase"."ai_sandboxes" y where y."chat_id" = marked."chat_id" and y."harness_id" = marked."harness_id" and y."status" <> 'stopped' order by y."last_used_at" desc limit 1), 'status', marked."status", 'lock_holder', marked."lock_holder", 'locked_until', marked."locked_until", 'last_active_at', marked."last_active_at", 'created_at', marked."created_at", 'updated_at', marked."updated_at")), '[]'::jsonb) into v_result from marked;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.idle_ai_sandboxes (
  batch         integer DEFAULT 50,
  lease_seconds integer DEFAULT 300
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
begin
  with due as (
    select y."id" from "better_supabase"."ai_sandboxes" y
    where ((y."status" = 'running' and (y."last_used_at" + make_interval(secs => y."idle_seconds") <= now() or y."expires_at" <= now()))
       or (y."status" = 'stopping' and y."updated_at" <= now() - make_interval(secs => greatest(idle_ai_sandboxes.lease_seconds, 1))))
      and not exists (
        select 1 from "better_supabase"."ai_harness_sessions" z
        where z."chat_id" = y."chat_id" and z."harness_id" = y."harness_id" and z."locked_until" > now()
      )
    order by y."last_used_at"
    limit least(greatest(idle_ai_sandboxes.batch, 1), 500)
    for update skip locked
  ), claimed as (
    update "better_supabase"."ai_sandboxes" x set "status" = 'stopping', "updated_at" = now()
    from due where x."id" = due."id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', claimed."id", 'organization_id', claimed."organization_id", 'user_id', claimed."user_id", 'chat_id', claimed."chat_id", 'harness_id', claimed."harness_id", 'provider', claimed."provider", 'sandbox_id', claimed."sandbox_id", 'container_id', claimed."container_id", 'status', claimed."status", 'metadata', claimed."metadata", 'idle_seconds', claimed."idle_seconds", 'error', claimed."error", 'last_used_at', claimed."last_used_at", 'expires_at', claimed."expires_at", 'stopped_at', claimed."stopped_at", 'created_at', claimed."created_at", 'updated_at', claimed."updated_at")), '[]') into v_rows from claimed;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.install_agent (
  tenant    uuid,
  agent_id  uuid,
  installed boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', install_agent.tenant, 'ai.read'), false) then
    raise exception 'you may not use agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  if not install_agent.installed then
    delete from "better_supabase"."agent_installs" n where n."agent_id" = install_agent.agent_id and n."user_id" = auth.uid() and n."organization_id" = install_agent.tenant;
    get diagnostics v_count = row_count;
    update "better_supabase"."agents" x set "install_count" = greatest(x."install_count" - v_count, 0) where x."id" = install_agent.agent_id;
    if v_count > 0 then
      perform better_supabase.audit_event(
    event_type => 'agent.uninstalled',
    category => 'ai',
    target_type => 'agent',
    record_id => install_agent.agent_id::text,
    tenant => (install_agent.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid())
  );
    end if;
    return v_count > 0;
  end if;
  if not exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."organization_id" in (select better_supabase.tenant_ids_with('ai.read'))))) or x."organization_id" in (select better_supabase.tenant_ids_with('ai.moderate')))) then
    raise exception 'agent % not found', install_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  insert into "better_supabase"."agent_installs" ("agent_id", "user_id", "organization_id") values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  update "better_supabase"."agents" x set "install_count" = x."install_count" + v_count where x."id" = install_agent.agent_id;
  if v_count > 0 then
    perform better_supabase.audit_event(
    event_type => 'agent.installed',
    category => 'ai',
    target_type => 'agent',
    record_id => install_agent.agent_id::text,
    tenant => (install_agent.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', install_agent.tenant::text, 'agentId', install_agent.agent_id, 'userId', auth.uid())
  );
  end if;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_sandboxes (
  tenant  uuid,
  chat_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'harness_id', x."harness_id", 'provider', x."provider", 'sandbox_id', x."sandbox_id", 'container_id', x."container_id", 'status', x."status", 'metadata', x."metadata", 'idle_seconds', x."idle_seconds", 'error', x."error", 'last_used_at', x."last_used_at", 'expires_at', x."expires_at", 'stopped_at', x."stopped_at", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."created_at" desc), '[]')
  from "better_supabase"."ai_sandboxes" x
  where x."organization_id" = list_ai_sandboxes.tenant and (list_ai_sandboxes.chat_id is null or x."chat_id" = list_ai_sandboxes.chat_id)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.load_ai_harness_session (
  chat    uuid,
  harness text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_harness_sessions";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."ai_harness_sessions" x
  where x."chat_id" = load_ai_harness_session.chat and x."harness_id" = load_ai_harness_session.harness;
  if not found then
    return null;
  end if;
  return jsonb_build_object('chat_id', v_row."chat_id", 'harness_id', v_row."harness_id", 'owner_id', v_row."owner_id", 'resume_state', v_row."resume_state", 'continue_state', v_row."continue_state", 'sandbox_id', (select y."sandbox_id" from "better_supabase"."ai_sandboxes" y where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped' order by y."last_used_at" desc limit 1), 'status', v_row."status", 'lock_holder', v_row."lock_holder", 'locked_until', v_row."locked_until", 'last_active_at', v_row."last_active_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_create (
  tenant           uuid,
  path             text,
  content          text,
  ns               jsonb   DEFAULT '{}'::jsonb,
  expected_version integer DEFAULT NULL::integer
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
  v_project uuid;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
begin
  v_scope := coalesce(memory_create.ns ->> 'scope', 'user');
  v_agent := (memory_create.ns ->> 'agent_id')::uuid;
  v_chat := (memory_create.ns ->> 'chat_id')::uuid;
  v_project := (memory_create.ns ->> 'project_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_create.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_create.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_create.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_create.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_create.path is null or length(memory_create.path) > 500 or memory_create.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_create.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_create.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if length(memory_create.content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_create.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null and x."path" = memory_create.path
  for update;
  if found then
    if memory_create.expected_version is not null and memory_create.expected_version <> v_row."version" then
      raise exception '% changed since version %', memory_create.path, memory_create.expected_version using errcode = '40001', hint = 'MEMORY_CONFLICT';
    end if;
    update "better_supabase"."memories" x set "content" = memory_create.content, "version" = x."version" + 1, "embedding" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  else
    if coalesce(memory_create.expected_version, 0) <> 0 then
      raise exception '% not found', memory_create.path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
    end if;
    insert into "better_supabase"."memories" ("organization_id", "owner_id", "scope", "agent_id", "chat_id", "project_id", "kind", "path", "content")
    values (memory_create.tenant, v_owner, v_scope, v_agent, v_chat, v_project, 'core', memory_create.path, memory_create.content)
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_delete (
  tenant uuid,
  path   text,
  ns     jsonb DEFAULT '{}'::jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_owner uuid;
  v_count integer;
begin
  v_scope := coalesce(memory_delete.ns ->> 'scope', 'user');
  v_agent := (memory_delete.ns ->> 'agent_id')::uuid;
  v_chat := (memory_delete.ns ->> 'chat_id')::uuid;
  v_project := (memory_delete.ns ->> 'project_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_delete.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_delete.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_delete.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_delete.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_delete.path is null or length(memory_delete.path) > 500 or memory_delete.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_delete.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_delete.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  delete from "better_supabase"."memories" x
  where x."organization_id" = memory_delete.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null
    and (x."path" = memory_delete.path or x."path" like replace(replace(memory_delete.path, '_', '\_'), '%', '\%') || '/%');
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_forget (
  memory_id     uuid,
  superseded_by uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."memories"%rowtype;
begin
  select * into v_row from "better_supabase"."memories" x where x."id" = memory_forget.memory_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or (v_row."scope" = 'organization' and coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false))) then
    return false;
  end if;
  if memory_forget.superseded_by is null then
    delete from "better_supabase"."memories" x where x."id" = v_row."id";
  else
    update "better_supabase"."memories" x set "superseded_by" = memory_forget.superseded_by, "updated_at" = now() where x."id" = v_row."id";
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_insert (
  tenant      uuid,
  path        text,
  insert_line integer,
  insert_text text,
  ns          jsonb   DEFAULT '{}'::jsonb
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
  v_project uuid;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
  v_lines text[];
  v_content text;
begin
  v_scope := coalesce(memory_insert.ns ->> 'scope', 'user');
  v_agent := (memory_insert.ns ->> 'agent_id')::uuid;
  v_chat := (memory_insert.ns ->> 'chat_id')::uuid;
  v_project := (memory_insert.ns ->> 'project_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_insert.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_insert.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_insert.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_insert.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_insert.path is null or length(memory_insert.path) > 500 or memory_insert.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_insert.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_insert.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_insert.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null and x."path" = memory_insert.path
  for update;
  if not found then
    raise exception '% not found', memory_insert.path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  v_lines := case when v_row."content" = '' then '{}'::text[] else string_to_array(v_row."content", E'\n') end;
  if memory_insert.insert_line < 0 or memory_insert.insert_line > coalesce(array_length(v_lines, 1), 0) then
    raise exception 'line % is outside the file', memory_insert.insert_line using errcode = '22023', hint = 'MEMORY_LINE';
  end if;
  v_content := array_to_string(v_lines[1:memory_insert.insert_line] || string_to_array(coalesce(memory_insert.insert_text, ''), E'\n') || v_lines[memory_insert.insert_line + 1:], E'\n');
  if length(v_content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  update "better_supabase"."memories" x set "content" = v_content, "version" = x."version" + 1, "embedding" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_list (
  tenant   uuid,
  ns       jsonb   DEFAULT '{}'::jsonb,
  kind     text    DEFAULT 'core'::text,
  max_rows integer DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_owner uuid;
  v_rows jsonb;
begin
  v_scope := coalesce(memory_list.ns ->> 'scope', 'user');
  v_agent := (memory_list.ns ->> 'agent_id')::uuid;
  v_chat := (memory_list.ns ->> 'chat_id')::uuid;
  v_project := (memory_list.ns ->> 'project_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_list.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_list.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_list.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."path", x."created_at" desc), '[]') into v_rows
  from (
    select * from "better_supabase"."memories" y
    where y."organization_id" = memory_list.tenant and y."owner_id" is not distinct from v_owner and y."scope" = v_scope and y."agent_id" is not distinct from v_agent and y."chat_id" is not distinct from v_chat and y."project_id" is not distinct from v_project and y."superseded_by" is null and y."kind" = memory_list.kind
    order by y."path", y."created_at" desc
    limit least(greatest(memory_list.max_rows, 1), 1000)
  ) x;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_rename (
  tenant   uuid,
  old_path text,
  new_path text,
  ns       jsonb DEFAULT '{}'::jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_owner uuid;
  v_count integer;
  v_prefix text := replace(replace(memory_rename.old_path, '_', '\_'), '%', '\%') || '/%';
begin
  v_scope := coalesce(memory_rename.ns ->> 'scope', 'user');
  v_agent := (memory_rename.ns ->> 'agent_id')::uuid;
  v_chat := (memory_rename.ns ->> 'chat_id')::uuid;
  v_project := (memory_rename.ns ->> 'project_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_rename.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_rename.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_rename.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_rename.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_rename.old_path is null or length(memory_rename.old_path) > 500 or memory_rename.old_path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_rename.old_path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_rename.old_path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if memory_rename.new_path is null or length(memory_rename.new_path) > 500 or memory_rename.new_path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_rename.new_path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_rename.new_path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if memory_rename.new_path = memory_rename.old_path or memory_rename.new_path like v_prefix then
    raise exception 'cannot move % into itself', memory_rename.old_path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if exists (
    select 1 from "better_supabase"."memories" x
    where x."organization_id" = memory_rename.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null
      and (x."path" = memory_rename.new_path or x."path" like replace(replace(memory_rename.new_path, '_', '\_'), '%', '\%') || '/%')
  ) then
    raise exception '% already exists', memory_rename.new_path using errcode = '23505', hint = 'MEMORY_EXISTS';
  end if;
  update "better_supabase"."memories" x set
    "path" = memory_rename.new_path || substr(x."path", length(memory_rename.old_path) + 1),
    "version" = x."version" + 1, "updated_at" = now()
  where x."organization_id" = memory_rename.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null
    and (x."path" = memory_rename.old_path or x."path" like v_prefix);
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception '% not found', memory_rename.old_path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_save (
  tenant            uuid,
  content           text,
  ns                jsonb             DEFAULT '{}'::jsonb,
  embedding         extensions.vector DEFAULT NULL::extensions.vector,
  model             text              DEFAULT NULL::text,
  source_message_id text              DEFAULT NULL::text
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
  v_project uuid;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
begin
  v_scope := coalesce(memory_save.ns ->> 'scope', 'user');
  v_agent := (memory_save.ns ->> 'agent_id')::uuid;
  v_chat := (memory_save.ns ->> 'chat_id')::uuid;
  v_project := (memory_save.ns ->> 'project_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_save.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_save.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_save.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_save.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if coalesce(length(memory_save.content), 0) = 0 then
    raise exception 'memory content is empty' using errcode = '22023', hint = 'MEMORY_EMPTY';
  end if;
  if length(memory_save.content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  insert into "better_supabase"."memories" ("organization_id", "owner_id", "scope", "agent_id", "chat_id", "project_id", "kind", "content", "embedding", "embedding_model", "source_message_id")
  values (memory_save.tenant, v_owner, v_scope, v_agent, v_chat, v_project, 'archival', memory_save.content, memory_save.embedding, memory_save.model, memory_save.source_message_id)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  v_project uuid;
  v_owner uuid;
  v_rows jsonb;
  v_candidates integer := least(greatest(memory_search.k, 1) * 4, 400);
  v_scan text := current_setting('hnsw.iterative_scan', true);
begin
  v_scope := coalesce(memory_search.ns ->> 'scope', 'user');
  v_agent := (memory_search.ns ->> 'agent_id')::uuid;
  v_chat := (memory_search.ns ->> 'chat_id')::uuid;
  v_project := (memory_search.ns ->> 'project_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_search.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_search.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_search.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  with scoped as materialized (
    select x."id" as id from "better_supabase"."memories" x
    where x."organization_id" = memory_search.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null and x."kind" = 'archival'
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
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'organization_id', t."organization_id", 'owner_id', t."owner_id", 'scope', t."scope", 'agent_id', t."agent_id", 'chat_id', t."chat_id", 'project_id', t."project_id", 'kind', t."kind", 'path', t."path", 'content', t."content", 'version', t."version", 'embedding_model', t."embedding_model", 'source_message_id', t."source_message_id", 'created_at', t."created_at", 'updated_at', t."updated_at") || jsonb_build_object('score', f.score, 'similarity', 1 - f.distance) order by f.score desc), '[]')
  into v_rows
  from fused f join "better_supabase"."memories" t on t."id" = f.id;
  perform set_config('hnsw.iterative_scan', coalesce(nullif(v_scan, ''), 'off'), true);
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_str_replace (
  tenant   uuid,
  path     text,
  old_text text,
  new_text text,
  ns       jsonb DEFAULT '{}'::jsonb
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
  v_project uuid;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
  v_matches integer;
begin
  v_scope := coalesce(memory_str_replace.ns ->> 'scope', 'user');
  v_agent := (memory_str_replace.ns ->> 'agent_id')::uuid;
  v_chat := (memory_str_replace.ns ->> 'chat_id')::uuid;
  v_project := (memory_str_replace.ns ->> 'project_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_str_replace.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_str_replace.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_str_replace.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_scope = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_str_replace.tenant, 'ai.admin'), false)) then
    raise exception 'only admins change organization memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_str_replace.path is null or length(memory_str_replace.path) > 500 or memory_str_replace.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_str_replace.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_str_replace.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_str_replace.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null and x."path" = memory_str_replace.path
  for update;
  if not found then
    raise exception '% not found', memory_str_replace.path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  if coalesce(length(memory_str_replace.old_text), 0) = 0 then
    raise exception 'old_text is empty' using errcode = '22023', hint = 'MEMORY_NO_MATCH';
  end if;
  v_matches := (length(v_row."content") - length(replace(v_row."content", memory_str_replace.old_text, ''))) / length(memory_str_replace.old_text);
  if v_matches = 0 then
    raise exception 'old_text does not appear in %', memory_str_replace.path using errcode = '22023', hint = 'MEMORY_NO_MATCH';
  elsif v_matches > 1 then
    raise exception 'old_text appears % times in %', v_matches, memory_str_replace.path using errcode = '22023', hint = 'MEMORY_AMBIGUOUS';
  end if;
  if length(replace(v_row."content", memory_str_replace.old_text, coalesce(memory_str_replace.new_text, ''))) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  update "better_supabase"."memories" x set
    "content" = replace(x."content", memory_str_replace.old_text, coalesce(memory_str_replace.new_text, '')),
    "version" = x."version" + 1, "embedding" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_view (
  tenant uuid,
  path   text  DEFAULT '/memories'::text,
  ns     jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
  v_entries jsonb;
begin
  v_scope := coalesce(memory_view.ns ->> 'scope', 'user');
  v_agent := (memory_view.ns ->> 'agent_id')::uuid;
  v_chat := (memory_view.ns ->> 'chat_id')::uuid;
  v_project := (memory_view.ns ->> 'project_id')::uuid;
  v_owner := case when v_scope = 'organization' then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_view.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_view.tenant, 'ai.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope <> 'organization' and v_owner is null) then
    raise exception 'ns % is not a memory namespace', memory_view.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if memory_view.path is null or length(memory_view.path) > 500 or memory_view.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_view.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_view.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_view.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null and x."path" = memory_view.path;
  if found then
    return jsonb_build_object('type', 'file', 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'updated_at', v_row."updated_at");
  end if;
  select jsonb_agg(jsonb_build_object('path', x."path", 'size', length(x."content"), 'updated_at', x."updated_at") order by x."path")
  into v_entries
  from "better_supabase"."memories" x
  where x."organization_id" = memory_view.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."superseded_by" is null and x."path" like replace(replace(memory_view.path, '_', '\_'), '%', '\%') || '/%';
  if v_entries is null and memory_view.path <> '/memories' then
    return null;
  end if;
  return jsonb_build_object('type', 'directory', 'path', memory_view.path, 'entries', coalesce(v_entries, '[]'));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_agent (
  id         uuid,
  visibility text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = publish_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.moderate'), false)) then
    raise exception 'agent % not found', publish_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if publish_agent.visibility <> 'private' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.moderate'), false)
    or (v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.share'), false))) then
    raise exception 'you may not publish agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."agents" x set
    "visibility" = publish_agent.visibility,
    "published_at" = case when publish_agent.visibility = 'private' then null else coalesce(x."published_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'agent.published',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug", 'visibility', publish_agent.visibility)
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rate_agent (
  agent_id uuid,
  rating   integer,
  comment  text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_old integer;
  v_row "better_supabase"."agents"%rowtype;
begin
  if auth.uid() is null then
    raise exception 'sign in to rate agents' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = rate_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."organization_id" in (select better_supabase.tenant_ids_with('ai.read'))))) or x."organization_id" in (select better_supabase.tenant_ids_with('ai.moderate'))) for update;
  if not found then
    raise exception 'agent % not found', rate_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if rate_agent.rating is not null and rate_agent.rating not between 1 and 5 then
    raise exception 'a rating is 1 to 5' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid()
  returning g."rating" into v_old;
  if rate_agent.rating is not null then
    insert into "better_supabase"."agent_ratings" ("agent_id", "user_id", "rating", "comment")
    values (v_row."id", auth.uid(), rate_agent.rating, rate_agent.comment);
  end if;
  update "better_supabase"."agents" x set
    "rating_count" = x."rating_count" - (case when v_old is null then 0 else 1 end) + (case when rate_agent.rating is null then 0 else 1 end),
    "rating_sum" = x."rating_sum" - coalesce(v_old, 0) + coalesce(rate_agent.rating, 0)
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_ai_batch (
  tenant    uuid,
  provider  text,
  reference jsonb,
  fields    jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ai_batches"%rowtype;
  v_fields jsonb := coalesce(record_ai_batch.fields, '{}');
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', record_ai_batch.tenant, 'ai.create'), false))) then
    raise exception 'you may not start batches here' using errcode = '42501', hint = 'AI_BATCH_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_batches" ("organization_id", "user_id", "provider", "reference", "status", "raw_status", "item_count", "counts", "metadata", "expires_at", "next_poll_at")
  values (
    record_ai_batch.tenant,
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (v_fields ->> 'user_id')::uuid else auth.uid() end,
    record_ai_batch.provider,
    record_ai_batch.reference,
    coalesce(v_fields ->> 'status', 'pending'),
    v_fields ->> 'raw_status',
    coalesce((v_fields ->> 'item_count')::integer, 0),
    coalesce(v_fields -> 'counts', '{}'),
    coalesce(v_fields -> 'metadata', '{}'),
    (v_fields ->> 'expires_at')::timestamptz,
    now() + interval '60 seconds'
  )
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'provider', v_row."provider", 'reference', v_row."reference", 'status', v_row."status", 'raw_status', v_row."raw_status", 'item_count', v_row."item_count", 'counts', v_row."counts", 'error', v_row."error", 'metadata', v_row."metadata", 'results_saved', v_row."results_saved", 'polls', v_row."polls", 'next_poll_at', v_row."next_poll_at", 'expires_at', v_row."expires_at", 'completed_at', v_row."completed_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_connector_grant (
  server_id      uuid,
  owner          uuid,
  credential_ref jsonb,
  scopes         text[]                   DEFAULT '{}'::text[],
  expires_at     timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_old "better_supabase"."connector_grants"%rowtype;
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = record_connector_grant.server_id;
  if not found then
    raise exception 'connector % not found', record_connector_grant.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.member_can(record_connector_grant.owner, v_server."organization_id", 'ai.create'), false) then
    raise exception 'the user may not use connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."server_id" = v_server."id" and y."user_id" = record_connector_grant.owner and y."revoked_at" is null
  returning * into v_old;
  insert into "better_supabase"."connector_grants" ("user_id", "server_id", "organization_id", "credential_ref", "scopes", "expires_at")
  values (record_connector_grant.owner, v_server."id", v_server."organization_id", record_connector_grant.credential_ref,
    coalesce(record_connector_grant.scopes, '{}'), record_connector_grant.expires_at)
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'connector_grant.created',
    category => 'integration',
    target_type => 'connector_grant',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'grantId', v_row."id", 'serverId', v_row."server_id", 'userId', v_row."user_id")
  );
  return jsonb_build_object('grant', jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at"), 'replaced', case when v_old."id" is null then null else jsonb_build_object('id', v_old."id", 'user_id', v_old."user_id", 'server_id', v_old."server_id", 'organization_id', v_old."organization_id", 'credential_ref', v_old."credential_ref", 'scopes', v_old."scopes", 'expires_at', v_old."expires_at", 'granted_at', v_old."granted_at", 'revoked_at', v_old."revoked_at") end);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_ai_sandbox (
  tenant     uuid,
  provider   text,
  sandbox_id text,
  fields     jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."ai_sandboxes"%rowtype;
  v_fields jsonb := coalesce(register_ai_sandbox.fields, '{}');
begin
  insert into "better_supabase"."ai_sandboxes" as cur ("organization_id", "user_id", "chat_id", "harness_id", "provider", "sandbox_id", "container_id", "metadata", "idle_seconds", "expires_at")
  values (
    register_ai_sandbox.tenant,
    (v_fields ->> 'user_id')::uuid,
    (v_fields ->> 'chat_id')::uuid,
    v_fields ->> 'harness_id',
    register_ai_sandbox.provider,
    register_ai_sandbox.sandbox_id,
    v_fields ->> 'container_id',
    coalesce(v_fields -> 'metadata', '{}'),
    coalesce((v_fields ->> 'idle_seconds')::integer, 600),
    (v_fields ->> 'expires_at')::timestamptz
  )
  on conflict ("provider", "sandbox_id") do update set
    "container_id" = coalesce(excluded."container_id", cur."container_id"),
    "chat_id" = coalesce(excluded."chat_id", cur."chat_id"),
    "harness_id" = coalesce(excluded."harness_id", cur."harness_id"),
    "metadata" = cur."metadata" || excluded."metadata",
    "idle_seconds" = excluded."idle_seconds",
    "expires_at" = coalesce(excluded."expires_at", cur."expires_at"),
    "status" = 'running',
    "error" = null,
    "stopped_at" = null,
    "last_used_at" = now(),
    "updated_at" = now()
  where cur."organization_id" = excluded."organization_id"
  returning * into v_row;
  if not found then
    raise exception 'sandbox % belongs to another tenant', register_ai_sandbox.sandbox_id using errcode = '42501', hint = 'AI_SANDBOX_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'harness_id', v_row."harness_id", 'provider', v_row."provider", 'sandbox_id', v_row."sandbox_id", 'container_id', v_row."container_id", 'status', v_row."status", 'metadata', v_row."metadata", 'idle_seconds', v_row."idle_seconds", 'error', v_row."error", 'last_used_at', v_row."last_used_at", 'expires_at', v_row."expires_at", 'stopped_at', v_row."stopped_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.release_ai_chat_stream (
  chat           uuid,
  stream         text,
  status         text   DEFAULT 'completed'::text,
  usage          jsonb  DEFAULT NULL::jsonb,
  generation_id  text   DEFAULT NULL::text,
  error          text   DEFAULT NULL::text,
  cost_micro_usd bigint DEFAULT NULL::bigint
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_status text := case coalesce(release_ai_chat_stream.status, 'completed')
    when 'done' then 'completed' when 'error' then 'failed' when 'stopped' then 'cancelled'
    else coalesce(release_ai_chat_stream.status, 'completed') end;
  v_found boolean := false;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if v_status not in ('completed', 'failed', 'cancelled') then
    raise exception 'A run ends completed, failed or cancelled, not %', v_status using errcode = '22023', hint = 'AI_RUN_INVALID';
  end if;
  update "better_supabase"."ai_runs" x set
    "status" = v_status,
    "usage" = coalesce(release_ai_chat_stream.usage, x."usage"),
    "provider_generation_id" = coalesce(release_ai_chat_stream.generation_id, x."provider_generation_id"),
    "error" = release_ai_chat_stream.error,
    "cost_micro_usd" = coalesce(release_ai_chat_stream.cost_micro_usd, x."cost_micro_usd"),
    "ended_at" = coalesce(x."ended_at", now())
  where x."chat_id" = release_ai_chat_stream.chat and x."stream_id" = release_ai_chat_stream.stream;
  update "better_supabase"."ai_chats" x set "active_stream_id" = null, "active_run_id" = null, "updated_at" = now()
  where x."id" = release_ai_chat_stream.chat and x."active_stream_id" = release_ai_chat_stream.stream
  returning true into v_found;
  if coalesce(v_found, false) then
    perform "better_supabase"."ai_chat_notify"(release_ai_chat_stream.chat, null, 'stream.ended', jsonb_build_object('streamId', release_ai_chat_stream.stream, 'status', v_status), false);
  end if;
  return coalesce(v_found, false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reserve_ai_file (
  tenant     uuid,
  filename   text,
  media_type text,
  byte_size  bigint,
  chat_id    uuid   DEFAULT NULL::uuid,
  project_id uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_files"%rowtype;
begin
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', reserve_ai_file.tenant, 'ai.create'), false) then
    raise exception 'you may not upload files here' using errcode = '42501', hint = 'AI_FILE_FORBIDDEN';
  end if;
  if byte_size < 0 or byte_size > 52428800 then
    raise exception 'files are limited to % bytes', 52428800 using errcode = '22023', hint = 'AI_FILE_TOO_LARGE';
  end if;
  insert into "better_supabase"."ai_files" ("organization_id", "owner_id", "chat_id", "project_id", "bucket", "filename", "media_type", "byte_size")
  values (reserve_ai_file.tenant, auth.uid(), reserve_ai_file.chat_id, reserve_ai_file.project_id, 'ai-files', reserve_ai_file.filename, lower(reserve_ai_file.media_type), reserve_ai_file.byte_size)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'bucket', v_row."bucket", 'path', v_row."path", 'media_type', v_row."media_type", 'filename', v_row."filename", 'byte_size', v_row."byte_size", 'sha256', v_row."sha256", 'status', v_row."status", 'source', v_row."source", 'created_at', v_row."created_at", 'uploaded_at', v_row."uploaded_at", 'expires_at', v_row."expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_ai_suggestion (
  suggestion_id uuid,
  accepted      boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_suggestions"%rowtype;
  v_doc "better_supabase"."ai_documents"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_suggestions" x where x."id" = resolve_ai_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from "better_supabase"."ai_documents" x where x."id" = v_row."document_id";
  end if;
  if v_doc."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_doc."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_doc."organization_id", 'ai.admin'), false)) then
    raise exception 'suggestion % not found', suggestion_id using errcode = 'P0002', hint = 'AI_SUGGESTION_NOT_FOUND';
  end if;
  update "better_supabase"."ai_suggestions" x set "resolved_at" = now(), "accepted" = resolve_ai_suggestion.accepted
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'document_id', v_row."document_id", 'version', v_row."version", 'original_text', v_row."original_text", 'suggested_text', v_row."suggested_text", 'description', v_row."description", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'resolved_at', v_row."resolved_at", 'accepted', v_row."accepted");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.role_permissions (
  role text
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case role
    when 'owner' then array['*']
    when 'admin' then array[
      'customers.read', 'customers.write', 'reports.read',
      'organization.read', 'organization.update',
      'members.read', 'members.invite', 'members.remove', 'members.update_role',
      'billing.read', 'billing.manage', 'audit.read',
      'settings.read', 'settings.update', 'settings.manage',
      'api_keys.manage', 'api_keys.own',
      'comments.read', 'comments.create', 'comments.moderate', 'activity.read',
      'onboarding.read', 'onboarding.complete', 'usage.read', 'usage.record',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'workflow.edit', 'workflow.publish', 'workflow.admin',
      'inbox.read', 'inbox.reply', 'inbox.assign', 'inbox.manage',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_chat.admin',
      'ai.read', 'ai.create', 'ai.share', 'ai.admin'
    ]
    when 'member' then array[
      'customers.read', 'organization.read', 'members.read', 'billing.read',
      'settings.read', 'api_keys.own', 'comments.read', 'comments.create', 'activity.read',
      'onboarding.read', 'usage.read', 'usage.record',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'inbox.read', 'inbox.reply',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share',
      'ai.read', 'ai.create', 'ai.share'
    ]
    else array[]::text[]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rollback_ai_document (
  document_id uuid,
  version     integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_documents"%rowtype;
  v_old "better_supabase"."ai_document_versions"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_documents" x where x."id" = rollback_ai_document.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'AI_DOCUMENT_NOT_FOUND';
  end if;
  select * into v_old from "better_supabase"."ai_document_versions" x where x."document_id" = v_row."id" and x."version" = rollback_ai_document.version;
  if not found then
    raise exception 'document % has no version %', document_id, rollback_ai_document.version using errcode = 'P0002', hint = 'AI_DOCUMENT_VERSION_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_document_versions" ("document_id", "version", "content", "storage_path", "created_by_message_id", "created_by")
  values (v_row."id", v_row."current_version" + 1, v_old."content", v_old."storage_path", null, auth.uid());
  update "better_supabase"."ai_documents" x set "current_version" = v_row."current_version" + 1, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'title', v_row."title", 'current_version', v_row."current_version", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_agent (
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
  v_row "better_supabase"."agents"%rowtype;
begin
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'ai.create'), false) then
      raise exception 'you may not create agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      raise exception 'a new agent needs a slug and a name' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    insert into "better_supabase"."agents" ("organization_id", "owner_id", "slug", "name")
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."agents" x where x."id" = save_agent.id and x."organization_id" = save_agent.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.moderate'), false)) then
      raise exception 'agent % not found', save_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."agents" x set
    "slug" = coalesce(save_agent.fields ->> 'slug', x."slug"),
    "name" = coalesce(save_agent.fields ->> 'name', x."name"),
    "description" = coalesce(save_agent.fields ->> 'description', x."description"),
    "instructions" = coalesce(save_agent.fields ->> 'instructions', x."instructions"),
    "model" = case when save_agent.fields ? 'model' then save_agent.fields ->> 'model' else x."model" end,
    "tools" = coalesce(save_agent.fields -> 'tools', x."tools"),
    "connector_ids" = case when save_agent.fields ? 'connector_ids'
      then array(select jsonb_array_elements_text(save_agent.fields -> 'connector_ids')::uuid)
      else x."connector_ids" end,
    "knowledge_scope" = coalesce(save_agent.fields -> 'knowledge_scope', x."knowledge_scope"),
    "starters" = coalesce(save_agent.fields -> 'starters', x."starters"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'agent.saved',
    category => 'ai',
    target_type => 'agent',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'agentId', v_row."id", 'slug', v_row."slug")
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
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
    -- A save without a status is a turn using the sandbox: an idle session
    -- turns active again, so a later idle_ai_harness_sessions finds it.
    "status" = coalesce(v_status, case when x."status" = 'idle' then 'active' else x."status" end),
    "last_active_at" = now(),
    "updated_at" = now()
  where x."chat_id" = v_row."chat_id" and x."harness_id" = v_row."harness_id"
  returning * into v_row;
  if save_ai_harness_session.fields ? 'sandbox_id' then
    if nullif(save_ai_harness_session.fields ->> 'sandbox_id', '') is null then
      update "better_supabase"."ai_sandboxes" y set "status" = 'stopped', "stopped_at" = now(), "updated_at" = now()
      where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped';
    else
      insert into "better_supabase"."ai_sandboxes" as cur ("organization_id", "user_id", "chat_id", "harness_id", "provider", "sandbox_id")
      values (v_chat."organization_id", v_chat."owner_id", v_chat."id", v_row."harness_id", coalesce(nullif(save_ai_harness_session.fields ->> 'sandbox_provider', ''), 'harness'), save_ai_harness_session.fields ->> 'sandbox_id')
      on conflict ("provider", "sandbox_id") do update set
        "chat_id" = excluded."chat_id",
        "harness_id" = excluded."harness_id",
        "status" = 'running',
        "error" = null,
        "stopped_at" = null,
        "last_used_at" = now(),
        "updated_at" = now()
      where cur."organization_id" = excluded."organization_id";
      if not found then
        raise exception 'sandbox % belongs to another tenant', save_ai_harness_session.fields ->> 'sandbox_id' using errcode = '42501', hint = 'AI_SANDBOX_FORBIDDEN';
      end if;
    end if;
  elsif save_ai_harness_session.fields ->> 'status' is null then
    update "better_supabase"."ai_sandboxes" y set "last_used_at" = now(), "updated_at" = now()
    where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" = 'running';
  end if;
  return jsonb_build_object('chat_id', v_row."chat_id", 'harness_id', v_row."harness_id", 'owner_id', v_row."owner_id", 'resume_state', v_row."resume_state", 'continue_state', v_row."continue_state", 'sandbox_id', (select y."sandbox_id" from "better_supabase"."ai_sandboxes" y where y."chat_id" = v_row."chat_id" and y."harness_id" = v_row."harness_id" and y."status" <> 'stopped' order by y."last_used_at" desc limit 1), 'status', v_row."status", 'lock_holder', v_row."lock_holder", 'locked_until', v_row."locked_until", 'last_active_at', v_row."last_active_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_provider_key.tenant, 'ai.admin'), false)) then
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
  perform better_supabase.audit_event(
    event_type => 'ai_provider_key.saved',
    category => 'security',
    target_type => 'ai_provider_key',
    record_id => v_row."id"::text,
    target_label => v_row."provider" || '/' || v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'keyId', v_row."id", 'provider', v_row."provider", 'name', v_row."name")
  );
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
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_task.tenant, 'ai.create'), false)) or auth.uid() is null then
      raise exception 'you may not schedule tasks here' using errcode = '42501', hint = 'AI_TASK_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_scheduled_tasks" ("organization_id", "user_id", "title", "prompt", "cron")
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id and x."organization_id" = save_ai_task.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'ai.admin'), false)) then
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
  perform better_supabase.audit_event(
    event_type => 'connector.saved',
    category => 'integration',
    target_type => 'connector',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'serverId', v_row."id", 'name', v_row."name")
  );
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_connector_session (
  server_id         uuid,
  chat_key          text  DEFAULT ''::text,
  session_id        text  DEFAULT NULL::text,
  initialize_result jsonb DEFAULT NULL::jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if auth.uid() is null then
    return false;
  end if;
  if save_connector_session.session_id is null and save_connector_session.initialize_result is null then
    delete from "better_supabase"."connector_sessions" z where z."server_id" = save_connector_session.server_id and z."user_id" = auth.uid()
      and z."chat_key" = coalesce(save_connector_session.chat_key, '');
    return true;
  end if;
  if not exists (select 1 from "better_supabase"."connector_grants" y where y."server_id" = save_connector_session.server_id and y."user_id" = auth.uid() and y."revoked_at" is null)
    and not exists (select 1 from "better_supabase"."connector_servers" x where x."id" = save_connector_session.server_id and x."auth_type" <> 'oauth' and coalesce(better_supabase.can('tenant', x."organization_id", 'ai.create'), false)) then
    return false;
  end if;
  insert into "better_supabase"."connector_sessions" ("server_id", "user_id", "chat_key", "session_id", "initialize_result", "expires_at")
  values (save_connector_session.server_id, auth.uid(), coalesce(save_connector_session.chat_key, ''), save_connector_session.session_id,
    save_connector_session.initialize_result, now() + interval '1 hour')
  on conflict ("server_id", "user_id", "chat_key") do update set
    "session_id" = excluded."session_id", "initialize_result" = excluded."initialize_result",
    "last_used_at" = now(), "expires_at" = excluded."expires_at";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_agent_skills (
  agent_id uuid,
  skills   jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
  v_items jsonb := case when jsonb_typeof(set_agent_skills.skills) = 'object' then set_agent_skills.skills -> 'items' else set_agent_skills.skills end;
  v_count integer;
begin
  select * into v_row from "better_supabase"."agents" x where x."id" = set_agent_skills.agent_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.moderate'), false)) then
    raise exception 'agent % not found', set_agent_skills.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if jsonb_typeof(v_items) is distinct from 'array' then
    raise exception 'skills must be a list' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id";
  insert into "better_supabase"."agent_skills" ("agent_id", "provider", "reference")
  select v_row."id", e ->> 'provider', e -> 'reference' from jsonb_array_elements(v_items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.suggest_ai_document_edit (
  document_id    uuid,
  original_text  text,
  suggested_text text,
  description    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_doc "better_supabase"."ai_documents"%rowtype;
  v_row "better_supabase"."ai_suggestions"%rowtype;
begin
  select * into v_doc from "better_supabase"."ai_documents" x where x."id" = suggest_ai_document_edit.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_doc."owner_id" = (select auth.uid()) or coalesce(better_supabase.can('tenant', v_doc."organization_id", 'ai.admin'), false) or (v_doc."chat_id" is not null and "better_supabase"."ai_chat_can_read"(v_doc."chat_id")))) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'AI_DOCUMENT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_suggestions" ("document_id", "version", "original_text", "suggested_text", "description", "created_by")
  values (v_doc."id", v_doc."current_version", suggest_ai_document_edit.original_text, suggest_ai_document_edit.suggested_text, suggest_ai_document_edit.description, auth.uid())
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'document_id', v_row."document_id", 'version', v_row."version", 'original_text', v_row."original_text", 'suggested_text', v_row."suggested_text", 'description', v_row."description", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'resolved_at', v_row."resolved_at", 'accepted', v_row."accepted");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_ai_document (
  document_id      uuid,
  content          text    DEFAULT NULL::text,
  title            text    DEFAULT NULL::text,
  message_id       text    DEFAULT NULL::text,
  expected_version integer DEFAULT NULL::integer,
  storage_path     text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_documents"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_documents" x where x."id" = update_ai_document.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'AI_DOCUMENT_NOT_FOUND';
  end if;
  if expected_version is not null and expected_version <> v_row."current_version" then
    raise exception 'document % is at version %', document_id, v_row."current_version" using errcode = '40001', hint = 'AI_DOCUMENT_CONFLICT';
  end if;
  insert into "better_supabase"."ai_document_versions" ("document_id", "version", "content", "storage_path", "created_by_message_id", "created_by")
  values (v_row."id", v_row."current_version" + 1, update_ai_document.content, update_ai_document.storage_path, update_ai_document.message_id, auth.uid());
  update "better_supabase"."ai_documents" x set
    "current_version" = v_row."current_version" + 1,
    "title" = coalesce(update_ai_document.title, x."title"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'chat_id', v_row."chat_id", 'kind', v_row."kind", 'title', v_row."title", 'current_version', v_row."current_version", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.write_knowledge_chunks (
  document_id uuid,
  chunks      jsonb,
  model       text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."knowledge_documents"%rowtype;
  v_count integer;
  v_keep boolean;
  v_items jsonb := case when jsonb_typeof(write_knowledge_chunks.chunks) = 'object' then write_knowledge_chunks.chunks -> 'items' else write_knowledge_chunks.chunks end;
begin
  select * into v_row from "better_supabase"."knowledge_documents" x where x."id" = write_knowledge_chunks.document_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    raise exception 'document % not found', document_id using errcode = 'P0002', hint = 'KNOWLEDGE_NOT_FOUND';
  end if;
  if coalesce(jsonb_typeof(v_items), '') <> 'array' or jsonb_array_length(v_items) > 10000 then
    raise exception 'chunks must be an array of at most 10000 chunks' using errcode = '22023', hint = 'KNOWLEDGE_CHUNKS';
  end if;
  v_count := jsonb_array_length(v_items);
  v_keep := write_knowledge_chunks.model is not distinct from v_row."embedding_model" or write_knowledge_chunks.model is null;
  insert into "better_supabase"."knowledge_chunks" as t ("document_id", "idx", "content", "token_count", "metadata")
  select v_row."id", (e.ord - 1)::integer, e.value ->> 'content', (e.value ->> 'tokens')::integer, coalesce(e.value -> 'metadata', '{}')
  from jsonb_array_elements(v_items) with ordinality e(value, ord)
  on conflict ("document_id", "idx") do update set
    "content" = excluded."content",
    "token_count" = excluded."token_count",
    "metadata" = excluded."metadata",
    "embedding" = case when v_keep and t."embedding_hash" = md5(excluded."content") then t."embedding" end,
    "embedding_hash" = case when v_keep and t."embedding_hash" = md5(excluded."content") then t."embedding_hash" end;
  delete from "better_supabase"."knowledge_chunks" x where x."document_id" = v_row."id" and x."idx" >= v_count;
  update "better_supabase"."knowledge_documents" x set
    "status" = case when exists (select 1 from "better_supabase"."knowledge_chunks" p where p."document_id" = x."id" and p."embedding" is null) then 'pending' else 'ready' end,
    "error" = null,
    "chunk_count" = v_count,
    "embedding_model" = coalesce(write_knowledge_chunks.model, x."embedding_model"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."status" = 'pending' then
  perform "better_supabase"."enqueue_job"(queue => 'knowledge_embed', payload => jsonb_build_object('document_id', v_row."id"), dedupe_key => 'knowledge:' || v_row."id"::text, dedupe_running => false);
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'scope_id', v_row."scope_id", 'file_id', v_row."file_id", 'title', v_row."title", 'source', v_row."source", 'metadata', v_row."metadata", 'status', v_row."status", 'error', v_row."error", 'chunk_count', v_row."chunk_count", 'embedding_model', v_row."embedding_model", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE INDEX ai_harness_sessions_idle_idx ON better_supabase.ai_harness_sessions USING btree (last_active_at)
  WHERE (status = 'active'::text);

CREATE UNIQUE INDEX memories_path_idx ON better_supabase.memories USING btree (organization_id, owner_id, scope, agent_id, chat_id, project_id, path) NULLS NOT DISTINCT
  WHERE ((path IS NOT NULL) AND (superseded_by IS NULL));

CREATE INDEX memories_project_idx ON better_supabase.memories USING btree (project_id)
  WHERE (project_id IS NOT NULL);

CREATE POLICY "agents_read" ON "better_supabase"."agents"
  FOR SELECT
  TO "authenticated"
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR ((published_at IS
    NOT NULL) AND
    ((visibility = 'public'::text) OR ((visibility = 'organization'::text) AND (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.read'::text) AS tenant_ids_with)))))
    OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.moderate'::text) AS tenant_ids_with))));

CREATE POLICY "ai_batches_read" ON "better_supabase"."ai_batches"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with))));

CREATE POLICY "ai_documents_read" ON "better_supabase"."ai_documents"
  FOR SELECT
  TO "authenticated"
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with)) OR ((chat_id IS
    NOT NULL) AND better_supabase.ai_chat_can_read(chat_id))));

CREATE POLICY "ai_files_read" ON "better_supabase"."ai_files"
  FOR SELECT
  TO "authenticated"
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with)) OR ((chat_id IS
    NOT NULL) AND better_supabase.ai_chat_can_read(chat_id))));

CREATE POLICY "ai_provider_keys_read" ON "better_supabase"."ai_provider_keys"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with)));

CREATE POLICY "ai_scheduled_tasks_read" ON "better_supabase"."ai_scheduled_tasks"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with))));

CREATE POLICY "ai_task_runs_read" ON "better_supabase"."ai_task_runs"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with))));

CREATE POLICY "connector_servers_read" ON "better_supabase"."connector_servers"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.read'::text) AS tenant_ids_with)));

CREATE POLICY "knowledge_documents_read" ON "better_supabase"."knowledge_documents"
  FOR SELECT
  TO "authenticated"
  USING
    (((owner_id = ( SELECT auth.uid() AS uid)) OR ((scope = ANY (ARRAY['organization'::text, 'agent'::text])) AND (organization_id IN ( SELECT
    better_supabase.tenant_ids_with('ai.read'::text) AS tenant_ids_with))) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.admin'::text) AS tenant_ids_with)) OR
    ((scope = 'chat'::text) AND ((scope_id IS NOT NULL) AND better_supabase.ai_chat_can_read(scope_id)))));

CREATE POLICY "memories_read" ON "better_supabase"."memories"
  FOR SELECT
  TO "authenticated"
  USING
    (((owner_id = ( SELECT auth.uid() AS uid)) OR ((scope = 'organization'::text) AND (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai.read'::text) AS
    tenant_ids_with)))));

REVOKE ALL ON FUNCTION "api"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint) TO "service_role";
