SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."team_members"
  DROP CONSTRAINT "team_members_pkey";

DROP FUNCTION "api"."add_team_member"(uuid, uuid);

DROP FUNCTION "api"."remove_team_member"(uuid, uuid);

DROP FUNCTION "better_supabase"."add_team_member"(uuid, uuid);

DROP FUNCTION "better_supabase"."remove_team_member"(uuid, uuid);

ALTER TABLE "better_supabase"."team_members"
  ADD COLUMN "employee_id" uuid;

ALTER TABLE "better_supabase"."team_members"
  ALTER COLUMN "user_id" DROP NOT NULL;

CREATE OR REPLACE FUNCTION api.add_team_member (
  team     uuid,
  member   uuid DEFAULT NULL::uuid,
  employee uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."add_team_member"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.remove_team_member (
  team     uuid,
  member   uuid DEFAULT NULL::uuid,
  employee uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_team_member"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.add_team_member (
  team     uuid,
  member   uuid DEFAULT NULL::uuid,
  employee uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_user uuid := add_team_member.member;
  v_employee uuid := add_team_member.employee;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = add_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if (add_team_member.member is null) = (add_team_member.employee is null) then
    raise exception 'pass either a user or an employee' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  if v_employee is null then
    if not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = v_user
  ) then
    raise exception 'user is not a member of the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
    v_employee := (
      select x."id" from "better_supabase"."employees" x
      where x."tenant_id" = v_tenant and x."user_id" = v_user
    );
  else
    select x."user_id" into v_user from "better_supabase"."employees" x
    where x."id" = v_employee and x."tenant_id" = v_tenant;
    if not found then
      raise exception 'employee is not in the tenant' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
    end if;
    if v_user is not null and not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_tenant
      and m."user_id" = v_user
  ) then
      v_user := null;
    end if;
  end if;
  if v_employee is not null and v_user is not null then
    delete from "better_supabase"."team_members" x
    where x."team_id" = add_team_member.team and x."user_id" = v_user and x."employee_id" is null
      and exists (
        select 1 from "better_supabase"."team_members" y
        where y."team_id" = add_team_member.team and y."employee_id" = v_employee
      );
    update "better_supabase"."team_members" set "user_id" = v_user
    where "team_id" = add_team_member.team and "employee_id" = v_employee and "user_id" is null;
    update "better_supabase"."team_members" set "employee_id" = v_employee
    where "team_id" = add_team_member.team and "user_id" = v_user and "employee_id" is null;
  end if;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "employee_id", "tenant_id")
  values (add_team_member.team, v_user, v_employee, v_tenant)
  on conflict do nothing;
  perform "better_supabase".emit_event('team_member.added', jsonb_build_object('organizationId', v_tenant, 'id', add_team_member.team, 'userId', v_user, 'employeeId', v_employee), 'teams/' || (add_team_member.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team_member.added',
    category => 'membership',
    target_type => 'team',
    record_id => (add_team_member.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', add_team_member.team, 'userId', v_user, 'employeeId', v_employee)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_employee_team_members()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_user uuid;
begin
  if new."user_id" is not null and exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = new."tenant_id"
      and m."user_id" = new."user_id"
  ) then
    v_user := new."user_id";
  end if;
  if tg_op = 'INSERT' or new."user_id" is distinct from old."user_id" then
    if v_user is not null then
      delete from "better_supabase"."team_members" x
      where x."user_id" = v_user and x."employee_id" is null
        and exists (
          select 1 from "better_supabase"."team_members" y
          where y."team_id" = x."team_id" and y."employee_id" = new."id"
        );
      update "better_supabase"."team_members" set "employee_id" = new."id"
      where "tenant_id" = new."tenant_id" and "user_id" = v_user and "employee_id" is null;
    end if;
    update "better_supabase"."team_members" set "user_id" = v_user
    where "employee_id" = new."id" and "user_id" is distinct from v_user;
  end if;
  if new."team_id" is not null and (tg_op = 'INSERT' or new."team_id" is distinct from old."team_id") then
    insert into "better_supabase"."team_members" ("team_id", "user_id", "employee_id", "tenant_id")
    select t."id", v_user, new."id", new."tenant_id"
    from "better_supabase"."teams" t
    where t."id" = new."team_id" and t."tenant_id" = new."tenant_id"
    on conflict do nothing;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_team_member_employee_keep()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if old."employee_id" is null or old."user_id" is null
    or not exists (select 1 from "better_supabase"."teams" t where t."id" = old."team_id")
    or not exists (select 1 from "better_supabase"."employees" x where x."id" = old."employee_id")
    or (exists (select 1 from auth.users u where u.id = old."user_id")
      and exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = old."tenant_id"
      and m."user_id" = old."user_id"
  )) then
    return old;
  end if;
  update "better_supabase"."team_members" set "user_id" = null
  where "team_id" = old."team_id" and "employee_id" = old."employee_id";
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_teams (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t."id",
    'name', t."name",
    'slug', t."slug",
    'description', t."description",
    'status', t."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = t."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = t."id"
    ), '[]'::jsonb)
  ) order by t."name"), '[]'::jsonb)
  from "better_supabase"."teams" t
  where t."tenant_id" = list_teams.tenant
    and (
      auth.role() = 'service_role'
      or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)
    )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_team_member (
  team     uuid,
  member   uuid DEFAULT NULL::uuid,
  employee uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_user uuid;
  v_employee uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = remove_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if (remove_team_member.member is null) = (remove_team_member.employee is null) then
    raise exception 'pass either a user or an employee' using errcode = '22023', hint = 'TEAM_MEMBER_INVALID';
  end if;
  delete from "better_supabase"."team_members" x
  where x."team_id" = remove_team_member.team
    and (x."employee_id" = remove_team_member.employee or x."user_id" = remove_team_member.member)
  returning x."user_id", x."employee_id" into v_user, v_employee;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('team_member.deleted', jsonb_build_object('organizationId', v_tenant, 'id', remove_team_member.team, 'userId', v_user, 'employeeId', v_employee), 'teams/' || (remove_team_member.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team_member.deleted',
    category => 'membership',
    target_type => 'team',
    record_id => (remove_team_member.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', remove_team_member.team, 'userId', v_user, 'employeeId', v_employee)
  );
  return true;
end;
$function$;

ALTER TABLE "better_supabase"."team_members"
  ADD CONSTRAINT "bsb_team_members_check" CHECK (((user_id IS NOT NULL) OR (employee_id IS NOT NULL)));

ALTER TABLE "better_supabase"."team_members"
  ADD CONSTRAINT "team_members_employee_fkey" FOREIGN KEY (employee_id) REFERENCES better_supabase.employees(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX bsb_team_members_employee_key ON better_supabase.team_members USING btree (team_id, employee_id)
  WHERE (employee_id IS NOT NULL);

CREATE UNIQUE INDEX bsb_team_members_user_key ON better_supabase.team_members USING btree (team_id, user_id)
  WHERE (user_id IS NOT NULL);

CREATE INDEX team_members_employee_idx ON better_supabase.team_members USING btree (employee_id)
  WHERE (employee_id IS NOT NULL);

CREATE TRIGGER bsb_employee_team_members
  AFTER INSERT OR UPDATE OF user_id, team_id ON better_supabase.employees
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_employee_team_members();

CREATE TRIGGER bsb_team_member_employee_keep
  BEFORE DELETE ON better_supabase.team_members
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_team_member_employee_keep();

REVOKE ALL ON FUNCTION "api"."add_team_member"(uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."add_team_member"(uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."remove_team_member"(uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_team_member"(uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."add_team_member"(uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."add_team_member"(uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."bsb_employee_team_members"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_team_member_employee_keep"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."remove_team_member"(uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_team_member"(uuid, uuid, uuid) TO "authenticated", "service_role";
