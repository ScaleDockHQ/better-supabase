SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.approval_eligible (
  request better_supabase.approval_requests
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."approval_eligible"($1) $function$;

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
    or (v_approvers ->> 'permission' is not null and "better_supabase"."approval_fact"(v_req."tenant_id", 'permission', v_approvers ->> 'permission', null))
    or (v_approvers ->> 'role' is not null and "better_supabase"."approval_fact"(v_req."tenant_id", 'role', v_approvers ->> 'role', null))
    or (v_approvers ->> 'team' is not null and "better_supabase"."approval_fact"(v_req."tenant_id", 'team', v_approvers ->> 'team', null))
    or (coalesce((v_approvers ->> 'manager')::boolean, false) and "better_supabase"."approval_fact"(v_req."tenant_id", 'manager', (v_req."policy" ->> 'managerOf'), v_req."requested_by"))) then
    return true;
  end if;
  if coalesce((v_step ->> 'escalated')::boolean, false) then
    v_approvers := v_step -> 'escalateTo';
    if ((coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and "better_supabase"."approval_fact"(v_req."tenant_id", 'permission', v_approvers ->> 'permission', null))
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
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_eligible.request_id;
  if not found then
    return false;
  end if;
  return "better_supabase"."approval_eligible"(v_req);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_eligible_ids (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select r."id" from "better_supabase"."approval_requests" r
  where r."status" = 'pending'
    and (approval_eligible_ids.tenant is null or r."tenant_id" = approval_eligible_ids.tenant)
    and "better_supabase"."approval_eligible"(r)
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
    when 'permission' then coalesce(better_supabase.can('tenant', approval_fact.tenant, approval_fact.value), false)
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

CREATE OR REPLACE FUNCTION better_supabase.approval_memo_bump()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform better_supabase.memo_set('approvals.gen', (coalesce(better_supabase.memo_get('approvals.gen'), '0')::bigint + 1)::text);
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.my_work (
  tenant    uuid    DEFAULT NULL::uuid,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind', w.kind,
      'subject', jsonb_build_object('type', w.subject_type, 'id', w.subject_id),
      'ref', w.ref,
      'title', coalesce(w.title, "better_supabase"."subject_title"(w.subject_type, w.subject_id)),
      'url', "better_supabase"."subject_url"(w.subject_type, w.subject_id),
      'at', w.at
    ) order by w.at desc nulls last, w.kind, w.ref), '[]'::jsonb)
    from (
      select * from (
    select 'mention'::text, c."subject_type"::text, c."subject_id"::text, m."id"::text, null::text,
      m."sent_at"
    from "better_supabase"."messages" m
    join "better_supabase"."conversations" c on c."id" = m."conversation_id" and c."kind" = 'subject'
    where v_me = any (m."mentions")
      and m."deleted_at" is null
      and m."sent_at" > now() - interval '30 days'
      and (my_work.tenant is null or m."tenant_id" = my_work.tenant)
    union all
    select 'reminder'::text, d.subject_type, d.subject_id, d.reminder::text, null::text, d.at
    from "better_supabase"."my_reminders_due"(my_work.tenant) d
    where "better_supabase"."can_subject"(d.subject_type, d.subject_id, 'read')
    union all
    select 'approval'::text, r."subject_type"::text, r."subject_id"::text, r."id"::text, null::text,
      r."created_at"
    from "better_supabase"."approval_requests" r
    where r."status" = 'pending'
      and (r."expires_at" is null or r."expires_at" > now())
      and (my_work.tenant is null or r."tenant_id" = my_work.tenant)
      and "better_supabase"."approval_eligible"(r)
    union all
    select 'assigned'::text, 'work_item'::text, i."id"::text, i."id"::text, i."title"::text,
      coalesce(i."due_at", a."created_at")
    from "better_supabase"."work_item_assignees" a
    join "better_supabase"."work_items" i on i."id" = a."work_item_id"
    where a."user_id" = v_me
      and i."state" not in ('completed', 'canceled')
      and i."archived_at" is null
      and (my_work.tenant is null or i."tenant_id" = my_work.tenant)
    union all
    select 'assigned'::text, 'maintenance_request'::text, i."id"::text, i."id"::text, i."title"::text,
      coalesce(i."due_at", a."created_at")
    from "better_supabase"."maintenance_request_assignees" a
    join "better_supabase"."maintenance_requests" i on i."id" = a."maintenance_request_id"
    where a."user_id" = v_me
      and i."state" not in ('completed', 'canceled')
      and i."archived_at" is null
      and (my_work.tenant is null or i."tenant_id" = my_work.tenant)
    union all
    select 'sla'::text, k."subject_type"::text, k."subject_id"::text, k."id"::text, null::text,
      k."due_at"
    from "better_supabase"."sla_clocks" k
    where k."subject_type" = 'work_item'
      and k."warned_at" is not null
      and k."met_at" is null
      and (my_work.tenant is null or k."tenant_id" = my_work.tenant)
      and exists (
        select 1 from "better_supabase"."work_item_assignees" a
        where a."work_item_id"::text = k."subject_id"::text
          and a."user_id" = v_me)
    union all
    select 'owned'::text, 'case'::text, c."id"::text, c."number"::text, c."title"::text,
      coalesce(c."due_on"::timestamptz, c."created_at")
    from "better_supabase"."cases" c
    where c."owner_id" = v_me
      and c."status" = 'open'
      and c."archived_at" is null
      and (my_work.tenant is null or c."tenant_id" = my_work.tenant)
      ) u (kind, subject_type, subject_id, ref, title, at)
      order by u.at desc nulls last, u.kind, u.ref
      limit least(greatest(coalesce(my_work.page_size, 50), 1), 200)
    ) w
  );
end;
$function$;

CREATE TRIGGER bsb_approval_memo
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.employees
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.approval_memo_bump();

CREATE TRIGGER bsb_approval_memo
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.team_members
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.approval_memo_bump();

CREATE TRIGGER bsb_approval_memo
  AFTER INSERT OR DELETE OR UPDATE ON public.memberships
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.approval_memo_bump();

REVOKE ALL ON FUNCTION "api"."approval_eligible"(better_supabase.approval_requests) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."approval_eligible"(better_supabase.approval_requests) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."approval_eligible"(better_supabase.approval_requests) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."approval_eligible"(better_supabase.approval_requests) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."approval_fact"(uuid, text, text, uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."approval_memo_bump"() FROM PUBLIC;
