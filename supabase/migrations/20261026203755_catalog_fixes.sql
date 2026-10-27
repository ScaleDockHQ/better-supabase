SET local check_function_bodies = off;
-- Replacing the team_members foreign key locks both tables.
set lock_timeout = '5s';

ALTER TABLE "better_supabase"."team_members"
  DROP CONSTRAINT "team_members_membership_fkey";

DROP FUNCTION "api"."create_team"(uuid, text, text);

DROP FUNCTION "api"."update_team"(uuid, text, text);

DROP FUNCTION "better_supabase"."create_team"(uuid, text, text);

DROP FUNCTION "better_supabase"."update_team"(uuid, text, text);

CREATE OR REPLACE FUNCTION api.create_team (
  tenant      uuid,
  name        text,
  description text,
  slug        text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_team"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.restore_team (
  team uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_team"($1) $function$;

CREATE OR REPLACE FUNCTION api.update_team (
  team        uuid,
  name        text,
  description text,
  patch       jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_team"($1, $2, $3, $4) $function$;

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
  v_approvers jsonb;
  v_me uuid := auth.uid();
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_eligible.request_id;
  if not found or v_me is null or v_req."status" <> 'pending' then
    return false;
  end if;
  if v_me = v_req."requested_by" and not coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) then
    return false;
  end if;
  if exists (
    select 1 from "better_supabase"."approval_decisions" x
    where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = v_me
  ) then
    return false;
  end if;
  if v_req."subject_type" = 'ai_tool_approval' then
    return "better_supabase"."ai_tool_approval_approvable"(v_req."subject_id");
  end if;
  v_approvers := v_req."policy" -> 'steps' -> v_req."step" -> 'approvers';
  return (coalesce(v_approvers -> 'users', '[]'::jsonb) ? v_me::text)
    or (v_approvers ->> 'permission' is not null and coalesce(better_supabase.can('tenant', v_req."tenant_id", v_approvers ->> 'permission'), false))
    or (v_approvers ->> 'role' is not null and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."user_id" = v_me and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_approvers ->> 'role')::text or r."key" = (v_approvers ->> 'role')::text) order by (r."id"::text = (v_approvers ->> 'role')::text) desc limit 1)
    ))
    or (v_approvers ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = v_approvers ->> 'team' and tm."user_id" = v_me))
    or exists (
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
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_notify.request_id;
  if not found then
    return;
  end if;
  if approval_notify.kind in ('approved', 'rejected', 'expired') then
    v_recipients := array[v_req."requested_by"];
    v_permission := null;
  else
    v_approvers := v_req."policy" -> 'steps' -> v_req."step" -> 'approvers';
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
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
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
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_team (
  tenant      uuid,
  name        text,
  description text,
  slug        text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_slug text := coalesce(create_team.slug, trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g')));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_team.tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_slug is null or v_slug = '' or (create_team.slug is not null and create_team.slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$') then
    raise exception 'team name needs a slug' using errcode = '22023', hint = 'TEAM_SLUG_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_team_create"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using create_team.tenant, v_slug;
    end if;
  end;
  insert into "better_supabase"."teams" ("tenant_id", "name", "slug", "description", "created_by")
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning "id" into v_id;
  perform "better_supabase".emit_event('team.created', jsonb_build_object('organizationId', create_team.tenant, 'id', v_id, 'name', create_team.name), 'teams/' || (v_id)::text, (create_team.tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.created',
    category => 'membership',
    target_type => 'team',
    record_id => (v_id)::text,
    tenant => (create_team.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', create_team.tenant, 'id', v_id, 'name', create_team.name)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_team_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, create_team.tenant;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_team (
  team uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = restore_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" set "status" = 'active', "updated_at" = now() where "id" = restore_team.team;
  perform "better_supabase".emit_event('team.restored', jsonb_build_object('organizationId', v_tenant, 'id', restore_team.team), 'teams/' || (restore_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.restored',
    category => 'membership',
    target_type => 'team',
    record_id => (restore_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', restore_team.team)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_team (
  team        uuid,
  name        text,
  description text,
  patch       jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if update_team.patch is not null and (jsonb_typeof(update_team.patch) <> 'object'
    or update_team.patch ? 'slug' and coalesce(update_team.patch ->> 'slug', '') !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    or update_team.patch ? 'name' and nullif(trim(update_team.patch ->> 'name'), '') is null) then
    raise exception 'patch sets name, slug or description; name and slug can''t be empty' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  update "better_supabase"."teams" as t
  set "name" = coalesce(update_team.patch ->> 'name', update_team.name, t."name"),
      "slug" = case when update_team.patch ? 'slug' then update_team.patch ->> 'slug' else t."slug" end,
      "description" = case when update_team.patch ? 'description' then update_team.patch ->> 'description' else coalesce(update_team.description, t."description") end,
      "updated_at" = now()
  where t."id" = update_team.team;
  perform "better_supabase".emit_event('team.updated', jsonb_build_object('organizationId', v_tenant, 'id', update_team.team, 'name', update_team.name), 'teams/' || (update_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.updated',
    category => 'membership',
    target_type => 'team',
    record_id => (update_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', update_team.team, 'name', update_team.name)
  );
  return jsonb_build_object('id', update_team.team);
end;
$function$;

ALTER TABLE "better_supabase"."team_members"
  ADD CONSTRAINT "team_members_membership_fkey" FOREIGN KEY (tenant_id, user_id) REFERENCES public.memberships(organization_id, user_id) ON DELETE CASCADE;

REVOKE ALL ON FUNCTION "api"."create_team"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_team"(uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_team"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_team"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_team"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_team"(uuid, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_team"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_team"(uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_team"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_team"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_team"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_team"(uuid, text, text, jsonb) TO "authenticated", "service_role";
