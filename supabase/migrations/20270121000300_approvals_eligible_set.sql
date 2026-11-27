SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.approval_eligible_ids_in (
  tenants uuid[]  DEFAULT NULL::uuid[],
  outside boolean DEFAULT false
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."approval_eligible_ids_in"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_eligible_ids (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS SETOF uuid
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  if approval_eligible_ids.tenant is not null then
    return query select x from "better_supabase"."approval_eligible_ids_in"(array[approval_eligible_ids.tenant]) as x;
    return;
  end if;
  return query
  select x from "better_supabase"."approval_eligible_ids_in"() as x
  union all
  select x from "better_supabase"."approval_eligible_ids_in"(outside => true) as x;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_eligible_ids_in (
  tenants uuid[]  DEFAULT NULL::uuid[],
  outside boolean DEFAULT false
)
  RETURNS SETOF uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenants uuid[] := coalesce(approval_eligible_ids_in.tenants, array(select better_supabase.member_organization_ids()));
begin
  if coalesce(approval_eligible_ids_in.outside, false) then
    return query
    with base as (
    select r.*, (select auth.uid()) as bsb_me from "better_supabase"."approval_requests" r
    where r."status" = 'pending' and (select auth.uid()) is not null
      and (r."tenant_id" is null or r."tenant_id" <> all (v_tenants))
  ),
  q as (
    select b.*, b."policy" -> 'steps' -> b."step" as bsb_step from base b
  ),
  needs as materialized (
    select distinct q."tenant_id" as t, s.ap ->> 'permission' as p
    from q, lateral (values ((q.bsb_step -> 'approvers'), (case when coalesce((q.bsb_step ->> 'escalated')::boolean, false) then (q.bsb_step -> 'escalateTo') end))) as s(ap)
    where s.ap ->> 'permission' is not null
  ),
  granted as materialized (
    select g.t, k.p from (select distinct n.p from needs n where n.t is not null) k
    cross join lateral better_supabase.tenant_ids_with(k.p) as g(t)
  )
  select q."id" from q
  where not exists (select 1 from "better_supabase"."approval_decisions" x where x."request_id" = q."id" and x."step" = q."step" and x."approver" = q.bsb_me)
    and not (coalesce(q."policy" -> 'excludedUserIds', '[]'::jsonb) ? q.bsb_me::text)
    and ((q.bsb_me = q."requested_by" and q."policy" ->> 'mode' = 'confirm')
      or ((q.bsb_me is distinct from q."requested_by" or coalesce((q."policy" ->> 'selfApproval')::boolean, false))
        and (case when q."subject_type" = 'support_request' then ("better_supabase"."support_request_approvable"(q."subject_id"::uuid))
          when q."subject_type" = 'ai_tool_approval' then ("better_supabase"."ai_tool_approval_approvable"(q."subject_id"))
          else (((coalesce((q.bsb_step -> 'approvers') -> 'users', '[]'::jsonb) ? q.bsb_me::text)
    or ((q.bsb_step -> 'approvers') ->> 'permission' is not null and exists (select 1 from granted g where g.t is not distinct from q."tenant_id" and g.p = (q.bsb_step -> 'approvers') ->> 'permission'))
    or ((q.bsb_step -> 'approvers') ->> 'role' is not null and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me and mm."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = ((q.bsb_step -> 'approvers') ->> 'role')::text or r."key" = ((q.bsb_step -> 'approvers') ->> 'role')::text) order by (r."id"::text = ((q.bsb_step -> 'approvers') ->> 'role')::text) desc limit 1)
    ))
    or ((q.bsb_step -> 'approvers') ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = (q.bsb_step -> 'approvers') ->> 'team' and tm."user_id" = q.bsb_me))
    or (coalesce(((q.bsb_step -> 'approvers') ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = q."tenant_id" and (case when (q."policy" ->> 'managerOf') is not null then me."id"::text = (q."policy" ->> 'managerOf') else me."user_id" = q."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = q.bsb_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me
    ))))
    or (coalesce((q.bsb_step ->> 'escalated')::boolean, false) and ((coalesce((q.bsb_step -> 'escalateTo') -> 'users', '[]'::jsonb) ? q.bsb_me::text)
    or ((q.bsb_step -> 'escalateTo') ->> 'permission' is not null and exists (select 1 from granted g where g.t is not distinct from q."tenant_id" and g.p = (q.bsb_step -> 'escalateTo') ->> 'permission'))
    or ((q.bsb_step -> 'escalateTo') ->> 'role' is not null and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me and mm."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = ((q.bsb_step -> 'escalateTo') ->> 'role')::text or r."key" = ((q.bsb_step -> 'escalateTo') ->> 'role')::text) order by (r."id"::text = ((q.bsb_step -> 'escalateTo') ->> 'role')::text) desc limit 1)
    ))
    or ((q.bsb_step -> 'escalateTo') ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = (q.bsb_step -> 'escalateTo') ->> 'team' and tm."user_id" = q.bsb_me))
    or (coalesce(((q.bsb_step -> 'escalateTo') ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = q."tenant_id" and (case when (q."policy" ->> 'managerOf') is not null then me."id"::text = (q."policy" ->> 'managerOf') else me."user_id" = q."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = q.bsb_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me
    )))))
    or exists (select 1 from "better_supabase"."approval_decisions" x where x."request_id" = q."id" and x."step" = q."step" and x."decision" = 'delegated' and x."delegate_to" = q.bsb_me)) end)));
  else
    return query
    with base as (
    select r.*, (select auth.uid()) as bsb_me from "better_supabase"."approval_requests" r
    where r."status" = 'pending' and (select auth.uid()) is not null
      and r."tenant_id" = any (v_tenants)
  ),
  q as (
    select b.*, b."policy" -> 'steps' -> b."step" as bsb_step from base b
  ),
  needs as materialized (
    select distinct q."tenant_id" as t, s.ap ->> 'permission' as p
    from q, lateral (values ((q.bsb_step -> 'approvers'), (case when coalesce((q.bsb_step ->> 'escalated')::boolean, false) then (q.bsb_step -> 'escalateTo') end))) as s(ap)
    where s.ap ->> 'permission' is not null
  ),
  granted as materialized (
    select g.t, k.p from (select distinct n.p from needs n where n.t is not null) k
    cross join lateral better_supabase.tenant_ids_with(k.p) as g(t)
  )
  select q."id" from q
  where not exists (select 1 from "better_supabase"."approval_decisions" x where x."request_id" = q."id" and x."step" = q."step" and x."approver" = q.bsb_me)
    and not (coalesce(q."policy" -> 'excludedUserIds', '[]'::jsonb) ? q.bsb_me::text)
    and ((q.bsb_me = q."requested_by" and q."policy" ->> 'mode' = 'confirm')
      or ((q.bsb_me is distinct from q."requested_by" or coalesce((q."policy" ->> 'selfApproval')::boolean, false))
        and (case when q."subject_type" = 'support_request' then ("better_supabase"."support_request_approvable"(q."subject_id"::uuid))
          when q."subject_type" = 'ai_tool_approval' then ("better_supabase"."ai_tool_approval_approvable"(q."subject_id"))
          else (((coalesce((q.bsb_step -> 'approvers') -> 'users', '[]'::jsonb) ? q.bsb_me::text)
    or ((q.bsb_step -> 'approvers') ->> 'permission' is not null and exists (select 1 from granted g where g.t is not distinct from q."tenant_id" and g.p = (q.bsb_step -> 'approvers') ->> 'permission'))
    or ((q.bsb_step -> 'approvers') ->> 'role' is not null and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me and mm."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = ((q.bsb_step -> 'approvers') ->> 'role')::text or r."key" = ((q.bsb_step -> 'approvers') ->> 'role')::text) order by (r."id"::text = ((q.bsb_step -> 'approvers') ->> 'role')::text) desc limit 1)
    ))
    or ((q.bsb_step -> 'approvers') ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = (q.bsb_step -> 'approvers') ->> 'team' and tm."user_id" = q.bsb_me))
    or (coalesce(((q.bsb_step -> 'approvers') ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = q."tenant_id" and (case when (q."policy" ->> 'managerOf') is not null then me."id"::text = (q."policy" ->> 'managerOf') else me."user_id" = q."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = q.bsb_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me
    ))))
    or (coalesce((q.bsb_step ->> 'escalated')::boolean, false) and ((coalesce((q.bsb_step -> 'escalateTo') -> 'users', '[]'::jsonb) ? q.bsb_me::text)
    or ((q.bsb_step -> 'escalateTo') ->> 'permission' is not null and exists (select 1 from granted g where g.t is not distinct from q."tenant_id" and g.p = (q.bsb_step -> 'escalateTo') ->> 'permission'))
    or ((q.bsb_step -> 'escalateTo') ->> 'role' is not null and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me and mm."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = ((q.bsb_step -> 'escalateTo') ->> 'role')::text or r."key" = ((q.bsb_step -> 'escalateTo') ->> 'role')::text) order by (r."id"::text = ((q.bsb_step -> 'escalateTo') ->> 'role')::text) desc limit 1)
    ))
    or ((q.bsb_step -> 'escalateTo') ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = (q.bsb_step -> 'escalateTo') ->> 'team' and tm."user_id" = q.bsb_me))
    or (coalesce(((q.bsb_step -> 'escalateTo') ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = q."tenant_id" and (case when (q."policy" ->> 'managerOf') is not null then me."id"::text = (q."policy" ->> 'managerOf') else me."user_id" = q."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = q.bsb_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me
    )))))
    or exists (select 1 from "better_supabase"."approval_decisions" x where x."request_id" = q."id" and x."step" = q."step" and x."decision" = 'delegated' and x."delegate_to" = q.bsb_me)) end)));
  end if;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."approval_eligible_ids_in"(uuid[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."approval_eligible_ids_in"(uuid[], boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."approval_eligible_ids_in"(uuid[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."approval_eligible_ids_in"(uuid[], boolean) TO "authenticated", "service_role";
