SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.save_approval_policy (
  tenant uuid,
  policy jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."approval_policies"%rowtype;
  v_row "better_supabase"."approval_policies"%rowtype;
  v_type text;
  v_action text;
  v_conditions jsonb;
  v_steps jsonb;
  v_step jsonb;
  v_fields jsonb;
  v_effect text;
  v_who jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_approval_policy.tenant, 'approvals.manage'), false)) then
    raise exception 'managing approval policies needs approvals.manage' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if jsonb_typeof(save_approval_policy.policy) is distinct from 'object' then
    raise exception 'policy must be an object' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if save_approval_policy.policy ? 'id' then
    select * into v_old from "better_supabase"."approval_policies" x
    where x."id" = (save_approval_policy.policy ->> 'id')::uuid and x."tenant_id" is not distinct from save_approval_policy.tenant
    for update;
    if not found then
      raise exception 'approval policy not found' using errcode = 'P0002', hint = 'APPROVAL_POLICY_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(save_approval_policy.policy ->> 'subjectType', v_old."subject_type");
  v_action := coalesce(save_approval_policy.policy ->> 'action', v_old."action");
  v_effect := case when save_approval_policy.policy ? 'effect' then nullif(save_approval_policy.policy ->> 'effect', '') else v_old."effect" end;
  if v_type is null or v_action is null or not (exists (
      select 1 from jsonb_array_elements('[{"subjectType":"*","action":"quote.send","effects":["money-movement"]},{"subjectType":"customer","action":"discount","effects":[]},{"subjectType":"customer","action":"refund","effects":[]},{"subjectType":"customer","action":"export","effects":[]},{"subjectType":"case","action":"close","effects":[]},{"subjectType":"drive_node","action":"approve","effects":[]},{"subjectType":"drive_node","action":"release","effects":[]},{"subjectType":"eve_tool_call","action":"add_note","effects":[]},{"subjectType":"workflow_run","action":"approve","effects":[]}]'::jsonb) f
      where (v_type = '*' or f.value ->> 'subjectType' in (v_type, '*'))
        and (v_action = '*' or f.value ->> 'action' in (v_action, '*'))
        and (v_effect is null or f.value -> 'effects' ? v_effect)
    )) then
    raise exception 'a tenant policy tightens an options.policies entry, and there is none for this subject type, action and effect' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  v_conditions := case when save_approval_policy.policy ? 'conditions' then nullif(save_approval_policy.policy -> 'conditions', 'null'::jsonb) else v_old."conditions" end;
  if v_conditions is not null then
    v_fields := "better_supabase"."rule_field_map"(v_type);
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'APPROVAL_FIELDS_MISSING';
    end if;
    perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  end if;
  v_steps := coalesce(save_approval_policy.policy -> 'steps', v_old."steps", '[]'::jsonb);
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) > 20 then
    raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager, decider }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager, decider }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager', 'decider'])
        or (v_who ? 'manager' and v_who -> 'manager' <> 'true'::jsonb)
        or (v_who ? 'decider' and v_who -> 'decider' <> 'true'::jsonb)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager, decider }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
      end if;
    end loop;
    if (v_step ? 'required' and v_step -> 'required' <> '"all"'::jsonb and (jsonb_typeof(v_step -> 'required') <> 'number' or (v_step ->> 'required')::numeric < 1
        or (v_step ->> 'required')::numeric <> trunc((v_step ->> 'required')::numeric)))
      or (v_step -> 'required' = '"all"'::jsonb and (v_step -> 'approvers') - 'permission' <> '{}'::jsonb
        and ((v_step -> 'approvers') - 'users' <> '{}'::jsonb or jsonb_array_length(v_step -> 'approvers' -> 'users') = 0))
      or (jsonb_typeof(v_step -> 'required') = 'number' and (v_step -> 'approvers') - 'users' = '{}'::jsonb
        and (v_step ->> 'required')::numeric > jsonb_array_length(v_step -> 'approvers' -> 'users'))
      or ((v_step ? 'escalateAfter') <> (v_step ? 'escalateTo'))
      or (v_step ? 'escalateAfter' and (jsonb_typeof(v_step -> 'escalateAfter') <> 'string' or (v_step ->> 'escalateAfter')::interval <= interval '0')) then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager, decider }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
  end loop;
  if exists (
    select 1 from jsonb_array_elements(v_steps) d(s)
    where d.s -> 'approvers' -> 'decider' = 'true'::jsonb or d.s -> 'escalateTo' -> 'decider' = 'true'::jsonb
  ) then
    raise exception 'decider is only valid for subject types a block decides' using errcode = '22023', hint = 'APPROVAL_POLICY_DECIDER_UNAVAILABLE';
  end if;
  v_steps := (select coalesce(jsonb_agg(case when s -> 'required' = '"all"'::jsonb and (s -> 'approvers') ? 'users'
    then jsonb_set(s, '{required}', to_jsonb(jsonb_array_length(s -> 'approvers' -> 'users'))) || '{"all": true}'::jsonb else s - 'all' end order by o), '[]'::jsonb)
    from jsonb_array_elements(v_steps) with ordinality e(s, o));
  if coalesce(save_approval_policy.policy ->> 'mode', v_old."mode"::text, 'authorize') not in ('confirm', 'authorize') then
    raise exception 'mode must be confirm or authorize' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."approval_policies" ("tenant_id", "subject_type", "action", "name", "conditions", "effect", "mode", "steps", "self_approval", "expires_in", "enabled", "created_by", "description")
    values (save_approval_policy.tenant, v_type, v_action, btrim(save_approval_policy.policy ->> 'name'), v_conditions, v_effect,
      coalesce(save_approval_policy.policy ->> 'mode', 'authorize'), v_steps,
      coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, false), (save_approval_policy.policy ->> 'expiresIn')::interval,
      coalesce((save_approval_policy.policy ->> 'enabled')::boolean, true), auth.uid(), case when coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb) ? 'description' then (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb) -> 'description')))."description" else better_supabase.column_default('"better_supabase"."approval_policies"', 'description', (null::"better_supabase"."approval_policies")."description") end)
    returning * into v_row;
  else
    update "better_supabase"."approval_policies" x set
      "subject_type" = v_type,
      "action" = v_action,
      "name" = coalesce(btrim(save_approval_policy.policy ->> 'name'), x."name"),
      "conditions" = v_conditions,
      "effect" = v_effect,
      "mode" = coalesce(save_approval_policy.policy ->> 'mode', x."mode"),
      "steps" = v_steps,
      "self_approval" = coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, x."self_approval"),
      "expires_in" = case when save_approval_policy.policy ? 'expiresIn' then (save_approval_policy.policy ->> 'expiresIn')::interval else x."expires_in" end,
      "enabled" = coalesce((save_approval_policy.policy ->> 'enabled')::boolean, x."enabled"),
      "updated_at" = now(), "description" = case when (save_approval_policy.policy -> 'fields') ? 'description' then (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', (save_approval_policy.policy -> 'fields') -> 'description')))."description" else x."description" end
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('approval_policy.created', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.created',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'created approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  else
    perform "better_supabase".emit_event('approval_policy.updated', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.updated',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'updated approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'action', v_row."action", 'effect', v_row."effect", 'name', v_row."name", 'conditions', v_row."conditions", 'mode', v_row."mode", 'steps', v_row."steps", 'selfApproval', v_row."self_approval", 'expiresIn', v_row."expires_in"::text, 'enabled', v_row."enabled", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('description', v_row."description"));
exception
  when invalid_text_representation or invalid_datetime_format or not_null_violation or check_violation then
    raise exception 'policy has an invalid name, mode, expiry or flag' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
end;
$function$;
