SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.approval_eligible (
  request better_supabase.approval_requests
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype := approval_eligible.request;
  v_step jsonb;
  v_approvers jsonb;
  v_me uuid := auth.uid();
begin
  if v_req."id" is null or v_me is null or v_req."status" <> 'pending' then
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
    or (v_approvers ->> 'role' is not null and "better_supabase"."approval_fact"(v_req."tenant_id", 'role', v_approvers ->> 'role', null))
    or (v_approvers ->> 'team' is not null and "better_supabase"."approval_fact"(v_req."tenant_id", 'team', v_approvers ->> 'team', null))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and "better_supabase"."approval_fact"(v_req."tenant_id", 'manager', (v_req."policy" ->> 'managerOf'), v_req."requested_by"))) then
    return true;
  end if;
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and "better_supabase"."approval_fact"(v_req."tenant_id", 'role', v_approvers ->> 'role', null))
    or (v_approvers ->> 'team' is not null and "better_supabase"."approval_fact"(v_req."tenant_id", 'team', v_approvers ->> 'team', null))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and "better_supabase"."approval_fact"(v_req."tenant_id", 'manager', (v_req."policy" ->> 'managerOf'), v_req."requested_by"))) then
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

CREATE OR REPLACE FUNCTION better_supabase.approval_fact (
  tenant    uuid,
  kind      text,
  value     text,
  requester uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_me uuid := auth.uid();
  v_key text := 'approvals.f' || md5(format('%s|%s|%s|%s|%s', v_me, approval_fact.tenant, approval_fact.kind, approval_fact.value, approval_fact.requester));
  v_stamp text := statement_timestamp()::text || '/' || coalesce(better_supabase.memo_get('approvals.gen'), '0');
  v_hit text := better_supabase.memo_get(v_key);
  v_result boolean;
begin
  if v_hit is not null and split_part(v_hit, '|', 1) = v_stamp then
    return split_part(v_hit, '|', 2) = 't';
  end if;
  v_result := coalesce(case approval_fact.kind
    when 'role' then exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = approval_fact.tenant and m."user_id" = v_me and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (approval_fact.value)::text or r."key" = (approval_fact.value)::text) order by (r."id"::text = (approval_fact.value)::text) desc limit 1)
    )
    when 'team' then exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = approval_fact.value and tm."user_id" = v_me)
    when 'manager' then (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = approval_fact.tenant and (case when approval_fact.value is not null then me."id"::text = approval_fact.value else me."user_id" = approval_fact.requester end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded'
      limit 1) = v_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = approval_fact.tenant and mm."user_id" = v_me
    ))
    else false
  end, false);
  perform better_supabase.memo_set(v_key, v_stamp || '|' || case when v_result then 't' else 'f' end);
  return v_result;
end;
$function$;

CREATE TRIGGER bsb_approval_memo
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.roles
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.approval_memo_bump();
