SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.approval_eligible (
  request_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_step jsonb;
  v_approvers jsonb;
  v_me uuid := auth.uid();
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_eligible.request_id;
  if not found or v_me is null or v_req."status" <> 'pending' then
    return false;
  end if;
  if exists (
    select 1 from "better_supabase"."approval_decisions" x
    where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = v_me
  ) then
    return false;
  end if;
  if v_me = v_req."requested_by" then
    if v_req."policy" ->> 'mode' = 'confirm' then
      return true;
    end if;
    if not coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) then
      return false;
    end if;
  end if;
  if v_req."subject_type" = 'ai_tool_approval' then
    return "better_supabase"."ai_tool_approval_approvable"(v_req."subject_id");
  end if;
  v_step := v_req."policy" -> 'steps' -> v_req."step";
  v_approvers := v_step -> 'approvers';
  if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_approvers ->> 'role')::text or r."key" = (v_approvers ->> 'role')::text) order by (r."id"::text = (v_approvers ->> 'role')::text) desc limit 1)
    ))
    or (v_approvers ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = v_approvers ->> 'team' and tm."user_id" = v_me))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded'
      limit 1) = v_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_req."tenant_id" and mm."user_id" = v_me
    )))) then
    return true;
  end if;
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_approvers ->> 'role')::text or r."key" = (v_approvers ->> 'role')::text) order by (r."id"::text = (v_approvers ->> 'role')::text) desc limit 1)
    ))
    or (v_approvers ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = v_approvers ->> 'team' and tm."user_id" = v_me))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded'
      limit 1) = v_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_req."tenant_id" and mm."user_id" = v_me
    )))) then
      return true;
    end if;
  end if;
  return exists (
      select 1 from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step"
        and x."decision" = 'delegated' and x."delegate_to" = v_me
    );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_notify (
  request_id uuid,
  kind       text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_approvers jsonb;
  v_permission text;
  v_recipients uuid[] := '{}';
  v_claims text;
  v_note jsonb;
  v_hook regprocedure;
  v_extra jsonb;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_notify.request_id;
  if not found then
    return;
  end if;
  if approval_notify.kind in ('approved', 'rejected', 'expired') then
    v_recipients := array[v_req."requested_by"];
    v_permission := null;
  else
    v_approvers := v_req."policy" -> 'steps' -> v_req."step" -> case when approval_notify.kind = 'escalated' then 'escalateTo' else 'approvers' end;
    v_permission := v_approvers ->> 'permission';
    v_recipients := array(
      select x::uuid from jsonb_array_elements_text(coalesce(v_approvers -> 'users', '[]'::jsonb)) x
      union
      select m."user_id" from "public"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_approvers ->> 'role')::text or r."key" = (v_approvers ->> 'role')::text) order by (r."id"::text = (v_approvers ->> 'role')::text) desc limit 1)
      union
      select tm."user_id" from "better_supabase"."team_members" tm
      where tm."team_id"::text = v_approvers ->> 'team'
      union
      select (select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded'
      limit 1) where coalesce((v_approvers ->> 'manager')::boolean, false)
      union
      select x."delegate_to" from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'delegated'
    );
    if approval_notify.kind = 'delegated' then
      v_recipients := array(
        select x."delegate_to" from "better_supabase"."approval_decisions" x
        where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'delegated'
        order by x."created_at" desc limit 1
      );
      v_permission := null;
    end if;
    -- Approvers who already decided this step aren't asked again.
    v_recipients := array(
      select u from unnest(v_recipients) u
      where not exists (
        select 1 from "better_supabase"."approval_decisions" x
        where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = u
      )
    );
  end if;
  if cardinality(v_recipients) = 0 and v_permission is null then
    return;
  end if;
  v_note := jsonb_build_object(
      'type', 'approval.' || approval_notify.kind,
      'tenant', v_req."tenant_id",
      'actor', coalesce(auth.uid(), v_req."requested_by"),
      'subject_type', v_req."subject_type",
      'subject_id', v_req."subject_id",
      'summary', left(v_req."action" || coalesce(': ' || v_req."reason", ''), 140),
      'recipients', to_jsonb(v_recipients),
      'permission', v_permission,
      'exclude', case when coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) or approval_notify.kind in ('approved', 'rejected', 'expired') then '[]'::jsonb else jsonb_build_array(v_req."requested_by") end,
      'include_actor', approval_notify.kind in ('approved', 'rejected', 'expired'),
      'key', 'approval.' || approval_notify.kind || ':' || v_req."id"::text || ':' || v_req."step"::text || ':' || extract(epoch from now())::bigint::text,
      'data', jsonb_build_object('requestId', v_req."id", 'action', v_req."action", 'step', v_req."step")
    );
  v_hook := to_regprocedure('"public"."approval_notification"(uuid, text, jsonb)');
  if v_hook is not null then
    execute format('select %s($1, $2, $3)', v_hook::oid::regproc) into v_extra
      using v_req."id", approval_notify.kind, v_note;
    if v_extra is null then
      return;
    end if;
    v_note := v_note || (v_extra - 'data') || jsonb_build_object('data', coalesce(v_note -> 'data', '{}'::jsonb) || coalesce(v_extra -> 'data', '{}'::jsonb));
  end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(v_note);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
end;
$function$;
