SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."workflow_step_library"
  ADD COLUMN "operation" text;

CREATE OR REPLACE FUNCTION better_supabase.actor_may_write()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case
    when auth.jwt() is null then true
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_tool_approval_approvable (
  approval_id text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_tool_approvals";
begin
  select * into v_row from "better_supabase"."ai_tool_approvals" x where x."approval_id" = ai_tool_approval_approvable.approval_id;
  return found and v_row."decision" is null and coalesce(v_row."owner_id" = (select auth.uid()), false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.apply_ai_tool_approval (
  approval_id text,
  approved    boolean,
  reason      text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."ai_tool_approvals";
  v_decision text := case when apply_ai_tool_approval.approved then 'approved' else 'denied' end;
begin
  select * into v_row from "better_supabase"."ai_tool_approvals" x where x."approval_id" = apply_ai_tool_approval.approval_id for update;
  if not found then
    raise exception 'No approval %', apply_ai_tool_approval.approval_id using errcode = 'P0002', hint = 'AI_APPROVAL_NOT_FOUND';
  end if;
  if apply_ai_tool_approval.approved is null then
    raise exception 'Approve or deny' using errcode = '22023', hint = 'AI_APPROVAL_INVALID';
  end if;
  if v_row."decision" is not null then
    if v_row."decision" = v_decision then
      return jsonb_build_object('approval_id', v_row."approval_id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'message_id', v_row."message_id", 'tool', v_row."tool", 'tool_call_id', v_row."tool_call_id", 'input', v_row."input", 'decision', v_row."decision", 'reason', v_row."reason", 'signature', v_row."signature", 'decided_by', v_row."decided_by", 'decided_at', v_row."decided_at", 'created_at', v_row."created_at");
    end if;
    raise exception 'Approval % was already %', v_row."approval_id", v_row."decision" using errcode = 'P0001', hint = 'AI_APPROVAL_DECIDED';
  end if;
  update "better_supabase"."ai_tool_approvals" x set
    "decision" = v_decision,
    "reason" = apply_ai_tool_approval.reason,
    "decided_by" = auth.uid(),
    "decided_at" = now()
  where x."approval_id" = v_row."approval_id"
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_row."chat_id", null, 'approval.decided', jsonb_build_object('approvalId', v_row."approval_id", 'decision', v_decision), false);
  perform better_supabase.audit_event(
    event_type => 'ai_tool_approval.decided',
    category => 'ai',
    target_type => 'ai_tool_approval',
    record_id => v_row."approval_id",
    target_label => v_row."tool",
    tenant => ((select c."organization_id" from "better_supabase"."ai_chats" c where c."id" = v_row."chat_id"))::uuid,
    metadata => jsonb_build_object('organizationId', (select c."organization_id" from "better_supabase"."ai_chats" c where c."id" = v_row."chat_id")::text, 'chatId', v_row."chat_id", 'approvalId', v_row."approval_id", 'tool', v_row."tool", 'decision', v_decision),
    idempotency_key => 'ai_tool_approval.decided:' || v_row."approval_id"
  );
  return jsonb_build_object('approval_id', v_row."approval_id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'message_id', v_row."message_id", 'tool', v_row."tool", 'tool_call_id', v_row."tool_call_id", 'input', v_row."input", 'decision', v_row."decision", 'reason', v_row."reason", 'signature', v_row."signature", 'decided_by', v_row."decided_by", 'decided_at', v_row."decided_at", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject_for (
  member       uuid,
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  case can_subject_for.subject_type
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.read'), false)
          else false
        end
      );
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_ai_tool_approval (
  approval_id text,
  approved    boolean,
  reason      text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."ai_tool_approvals";
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_row from "better_supabase"."ai_tool_approvals" x where x."approval_id" = decide_ai_tool_approval.approval_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid())) then
    raise exception 'No approval %', decide_ai_tool_approval.approval_id using errcode = 'P0002', hint = 'AI_APPROVAL_NOT_FOUND';
  end if;
  return "better_supabase"."apply_ai_tool_approval"(decide_ai_tool_approval.approval_id, decide_ai_tool_approval.approved, decide_ai_tool_approval.reason);
end;
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
  v_permissions text[];
  v_missing text[];
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
  end if;
  v_errors := "better_supabase"."validate_workflow_graph"(v_row."graph");
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  v_permissions := "better_supabase"."workflow_graph_permissions"(v_row."graph");
  if not v_service then
    select array_agg(p order by p) into v_missing
    from unnest(v_permissions) p
    where not coalesce(better_supabase.can('tenant', v_tenant, p), false);
    if v_missing is not null then
      raise exception 'You may not publish a workflow whose steps need %', array_to_string(v_missing, ', ')
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_FORBIDDEN',
          detail = jsonb_build_object('permissions', to_jsonb(v_missing))::text;
    end if;
  end if;
  update "better_supabase"."workflow_versions" x set "status" = 'archived'
  where x."definition_id" = v_row."definition_id" and x."status" = 'published';
  update "better_supabase"."workflow_versions" x set
    "status" = 'published',
    "compiled" = compiled,
    "published_at" = now(),
    "published_by" = case when v_service then null else (select auth.uid()) end,
    "owner_kind" = case when v_service then 'organization' else 'user' end,
    "permissions" = v_permissions
  where x."id" = v_row."id"
  returning * into v_row;
  perform better_supabase.audit_event(
    event_type => 'workflow.published',
    category => 'configuration',
    target_type => 'workflow_version',
    record_id => v_row."id"::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant::text, 'definitionId', v_row."definition_id", 'versionId', v_row."id", 'version', v_row."version"),
    idempotency_key => 'workflow.published:' || v_row."id"::text
  );
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'publishedBy', v_row."published_by",
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions"),
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
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
  insert into "better_supabase"."workflow_step_library" ("name", "title", "description", "input_schema", "output_schema", "credential_kind", "operation")
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
  delete from "better_supabase"."workflow_step_library" x
  where not exists (
    select 1 from jsonb_each(coalesce(steps, '{}'::jsonb)) e where e.key = x."name"
  );
  select count(*) into v_count from "better_supabase"."workflow_step_library";
  return v_count;
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
        from "better_supabase"."workflow_step_library" s where s."name" = n.value ->> 'step'),
      'workflow.run'
    ) as p
    from jsonb_array_elements(
      case when jsonb_typeof(workflow_graph_permissions.graph -> 'nodes') = 'array'
        then workflow_graph_permissions.graph -> 'nodes' else '[]'::jsonb end
    ) n
    where n.value ->> 'kind' = 'step'
  ) x;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_run_principal (
  version uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
  v_publisher uuid;
  v_missing text;
begin
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'This workflow version was never published' using errcode = 'P0002', hint = 'WORKFLOW_NOT_PUBLISHED';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if v_row."owner_kind" is null then
    raise exception 'This workflow version was published before publishers were recorded; publish it again'
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';
  end if;
  if v_row."owner_kind" = 'user' then
    if v_row."published_by" is null then
      raise exception 'The user who published this workflow no longer exists'
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';
    end if;
    select string_agg(p, ', ' order by p) into v_missing
    from unnest(array_append(v_row."permissions", 'workflow.publish')) p
    where not coalesce(better_supabase.can_user(v_row."published_by", 'tenant', v_tenant, p), false);
    if v_missing is not null then
      raise exception 'The user who published this workflow no longer holds %', v_missing
        using errcode = '42501', hint = 'WORKFLOW_PUBLISHER_REVOKED';
    end if;
  end if;
  return jsonb_build_object(
    'publisher', coalesce(v_publisher, v_row."published_by"),
    'tenant', v_tenant,
    'owner', v_row."owner_kind",
    'permissions', to_jsonb(v_row."permissions")
  );
end;
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
  ) order by x."name"), '[]'::jsonb) from "better_supabase"."workflow_step_library" x;
$function$;

ALTER TABLE "better_supabase"."workflow_step_library"
  ADD CONSTRAINT "workflow_step_library_operation_check" CHECK (((length(operation) >= 1) AND (length(operation) <= 200)));

REVOKE ALL ON FUNCTION "better_supabase"."ai_tool_approval_approvable"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."apply_ai_tool_approval"(text, boolean, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."can_subject_for"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can_subject_for"(uuid, text, text, text) TO "service_role";
