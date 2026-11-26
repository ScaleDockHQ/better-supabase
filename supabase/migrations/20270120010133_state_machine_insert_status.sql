SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_drive_node()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' then
    
    -- A new row starts where the initial status can go in one step; only an
    -- import run or the service role creates one further along.
    if new."document_status"::text not in ('draft', 'in_review')
      and not (better_supabase.import_run() is not null) and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'a new record can''t start in that status' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
    end if;
    -- An import run (ADR 0141) may insert a row in any status: one synthetic
    -- imported history row stands for how it got there, and no event fires.
    if better_supabase.import_run() is not null and new."document_status" is not null then
      insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'drive_node', new."id"::text, null::text, new."document_status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), 'imported', nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
    end if;
    
    
    return new;
  end if;
  if new."document_status" is not distinct from old."document_status" then
    return new;
  end if;
  -- An import may set a status the state machine would refuse. The import
  -- already checked the row.
  if better_supabase.import_run() is not null then
    return new;
  end if;
  if new."document_status" is null or not (old."document_status" is null and new."document_status"::text = 'draft') and not (case old."document_status"::text when 'draft' then new."document_status"::text = any ('{in_review}'::text[]) when 'in_review' then new."document_status"::text = any ('{draft,effective}'::text[]) when 'effective' then new."document_status"::text = any ('{obsolete}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  -- The approvals module sets better_supabase.approval to the request it
  -- just approved before it makes the transition.
  if (case old."document_status"::text when 'in_review' then new."document_status"::text = any ('{effective}'::text[]) else false end)
    and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    and not exists (
      select 1 from "better_supabase"."approval_requests" a
      where a."id"::text = nullif(current_setting('better_supabase.approval', true), '')
        and a."status" = 'approved'
        and a."subject_type" = 'drive_node'
        and a."subject_id" = new."id"::text
    ) then
    raise exception 'that status change needs an approved request' using errcode = '42501', hint = 'STATE_APPROVAL_REQUIRED';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'drive_node', new."id"::text, old."document_status"::text, new."document_status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', new."id"::text, 'from', old."document_status"::text, 'to', new."document_status"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/drive_node/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_warranty_claim()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' then
    if new."status" is null then
      new."status" := 'draft';
    end if;
    -- A new row starts where the initial status can go in one step; only an
    -- import run or the service role creates one further along.
    if new."status"::text not in ('draft', 'submitted')
      and not (better_supabase.import_run() is not null) and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'a new record can''t start in that status' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
    end if;
    -- An import run (ADR 0141) may insert a row in any status: one synthetic
    -- imported history row stands for how it got there, and no event fires.
    if better_supabase.import_run() is not null and new."status" is not null then
      insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'warranty_claim', new."id"::text, null::text, new."status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), 'imported', nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
    end if;
    
    
    return new;
  end if;
  if new."status" is not distinct from old."status" then
    return new;
  end if;
  -- An import may set a status the state machine would refuse. The import
  -- already checked the row.
  if better_supabase.import_run() is not null then
    return new;
  end if;
  if not (case old."status"::text when 'draft' then new."status"::text = any ('{submitted}'::text[]) when 'submitted' then new."status"::text = any ('{approved,denied}'::text[]) when 'approved' then new."status"::text = any ('{closed}'::text[]) when 'denied' then new."status"::text = any ('{closed}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'warranty_claim', new."id"::text, old."status"::text, new."status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'warranty_claim', 'subjectId', new."id"::text, 'from', old."status"::text, 'to', new."status"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/warranty_claim/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_work_item()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' then
    if new."state" is null then
      new."state" := 'backlog';
    end if;
    -- A new row starts where the initial status can go in one step; only an
    -- import run or the service role creates one further along.
    if new."state"::text not in ('backlog', 'triage', 'unstarted', 'started', 'completed', 'canceled')
      and not (better_supabase.import_run() is not null) and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
      raise exception 'a new record can''t start in that status' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
    end if;
    -- An import run (ADR 0141) may insert a row in any status: one synthetic
    -- imported history row stands for how it got there, and no event fires.
    if better_supabase.import_run() is not null and new."state" is not null then
      insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'work_item', new."id"::text, null::text, new."state"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), 'imported', nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
    end if;
    
    
    return new;
  end if;
  if new."state" is not distinct from old."state" then
    return new;
  end if;
  -- An import may set a status the state machine would refuse. The import
  -- already checked the row.
  if better_supabase.import_run() is not null then
    return new;
  end if;
  if not (case old."state"::text when 'triage' then new."state"::text = any ('{backlog,unstarted,started,completed,canceled}'::text[]) when 'backlog' then new."state"::text = any ('{triage,unstarted,started,completed,canceled}'::text[]) when 'unstarted' then new."state"::text = any ('{triage,backlog,started,completed,canceled}'::text[]) when 'started' then new."state"::text = any ('{triage,backlog,unstarted,completed,canceled}'::text[]) when 'completed' then new."state"::text = any ('{triage,backlog,unstarted,started,canceled}'::text[]) when 'canceled' then new."state"::text = any ('{triage,backlog,unstarted,started,completed}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'work_item', new."id"::text, old."state"::text, new."state"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'work_item', 'subjectId', new."id"::text, 'from', old."state"::text, 'to', new."state"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/work_item/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;
