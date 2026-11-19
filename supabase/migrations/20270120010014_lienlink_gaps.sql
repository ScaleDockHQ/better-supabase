SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.compute_deadlines_many (
  tenant uuid,
  items  jsonb,
  prune  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."compute_deadlines_many"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.prune_deadlines (
  tenant            uuid,
  subject_type      text,
  subject_id        text,
  keep_jurisdiction text    DEFAULT NULL::text,
  pending_only      boolean DEFAULT true
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."prune_deadlines"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.purge_teams (
  team_ids uuid[]
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_teams"($1) $function$;

CREATE OR REPLACE FUNCTION api.resend_invitations (
  invitation_ids uuid[],
  valid_for      interval DEFAULT '7 days'::interval
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."resend_invitations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.add_person_identity (
  person   uuid,
  channel  text,
  address  text,
  verified boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_channel text := nullif(trim(add_person_identity.channel), '');
  v_address text := nullif(trim(add_person_identity.address), '');
  v_holder uuid;
  v_row jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select p."tenant_id" into v_tenant from "better_supabase"."people" p
  where p."id" = add_person_identity.person and p."merged_into" is null;
  if v_tenant is null then
    raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if v_channel is null or v_address is null then
    raise exception 'an identity needs a channel and an address' using errcode = '22023', hint = 'PARTY_IDENTITY_INVALID';
  end if;
  select i."person_id" into v_holder from "better_supabase"."person_identities" i
  where i."tenant_id" = v_tenant and i."channel" = v_channel and i."address" = v_address;
  if v_holder is not null and v_holder <> add_person_identity.person then
    raise exception 'another person has this address' using errcode = '23505', hint = 'PARTY_IDENTITY_TAKEN';
  end if;
  insert into "better_supabase"."person_identities" ("tenant_id", "person_id", "channel", "address", "verified_at")
  values (v_tenant, add_person_identity.person, v_channel, v_address, case when add_person_identity.verified then now() end)
  on conflict do nothing;
  if add_person_identity.verified then
    update "better_supabase"."person_identities" i set "verified_at" = coalesce(i."verified_at", now())
    where i."tenant_id" = v_tenant and i."channel" = v_channel and i."address" = v_address;
  end if;
  select jsonb_build_object('id', i."id", 'tenant_id', i."tenant_id", 'person_id', i."person_id", 'channel', i."channel", 'address', i."address", 'verified_at', i."verified_at", 'created_at', i."created_at") into v_row from "better_supabase"."person_identities" i
  where i."tenant_id" = v_tenant and i."channel" = v_channel and i."address" = v_address;
  return v_row;
end;
$function$;

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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
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

CREATE OR REPLACE FUNCTION better_supabase.archive_company (
  id       uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_name text;
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."name", x."archived_at" into v_tenant, v_name, v_was from "better_supabase"."companies" x where x."id" = archive_company.id;
  if v_tenant is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."companies" x set "archived_at" = case when archive_company.archived then coalesce(x."archived_at", now()) end, "updated_at" = now()
    where x."id" = archive_company.id;
  exception when unique_violation then
    raise exception 'another company has this domain' using errcode = '23505', hint = 'PARTY_DOMAIN_TAKEN';
  end;
  if archive_company.archived then
    perform "better_supabase".emit_event('company.archived', jsonb_build_object('organizationId', v_tenant, 'companyId', archive_company.id, 'name', v_name), 'companies/' || archive_company.id::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  elsif v_was is not null then
    perform "better_supabase".emit_event('company.restored', jsonb_build_object('organizationId', v_tenant, 'companyId', archive_company.id, 'name', v_name), 'companies/' || archive_company.id::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_person (
  id       uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_name text;
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."name", x."archived_at" into v_tenant, v_name, v_was from "better_supabase"."people" x where x."id" = archive_person.id;
  if v_tenant is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."people" x set "archived_at" = case when archive_person.archived then coalesce(x."archived_at", now()) end, "updated_at" = now()
    where x."id" = archive_person.id;
  exception when unique_violation then
    raise exception 'another person has this email' using errcode = '23505', hint = 'PARTY_EMAIL_TAKEN';
  end;
  if archive_person.archived then
    perform "better_supabase".emit_event('person.archived', jsonb_build_object('organizationId', v_tenant, 'personId', archive_person.id, 'name', v_name), 'persons/' || archive_person.id::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  elsif v_was is not null then
    perform "better_supabase".emit_event('person.restored', jsonb_build_object('organizationId', v_tenant, 'personId', archive_person.id, 'name', v_name), 'persons/' || archive_person.id::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_team (
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
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = archive_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" set "status" = 'archived', "updated_at" = now() where "id" = archive_team.team;
  perform "better_supabase".emit_event('team.archived', jsonb_build_object('organizationId', v_tenant, 'id', archive_team.team), 'teams/' || (archive_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.archived',
    category => 'membership',
    target_type => 'team',
    record_id => (archive_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', archive_team.team)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.compute_deadlines_many (
  tenant uuid,
  items  jsonb,
  prune  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_item jsonb;
  v_out jsonb := '[]'::jsonb;
  v_hint text;
  v_message text;
begin
  if jsonb_typeof(compute_deadlines_many.items) is distinct from 'array' or jsonb_array_length(compute_deadlines_many.items) > 1000 then
    raise exception 'items is a list of at most 1000 subjects' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(compute_deadlines_many.items) loop
    begin
      if compute_deadlines_many.prune then
        perform "better_supabase"."prune_deadlines"(compute_deadlines_many.tenant, v_item ->> 'subjectType', v_item ->> 'subjectId', v_item ->> 'jurisdiction');
      end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'subjectType', v_item ->> 'subjectType',
        'subjectId', v_item ->> 'subjectId',
        'ok', true,
        'deadlines', "better_supabase"."compute_deadlines"(
          compute_deadlines_many.tenant,
          v_item ->> 'subjectType',
          v_item ->> 'subjectId',
          v_item ->> 'jurisdiction',
          v_item ->> 'kind',
          coalesce(v_item -> 'facts', '{}'::jsonb),
          coalesce((v_item ->> 'asOf')::date, current_date),
          v_item ->> 'group'
        )
      ));
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_message = message_text;
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'subjectType', v_item ->> 'subjectType',
        'subjectId', v_item ->> 'subjectId',
        'ok', false,
        'hint', nullif(v_hint, ''),
        'message', v_message
      ));
    end;
  end loop;
  return v_out;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_team.tenant, 'teams.manage'), false)) then
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

CREATE OR REPLACE FUNCTION better_supabase.deadlines_subject_deleted_product()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."deadlines" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."deadlines" x where x."subject_type" = v_type and x."subject_id" = v_id and x."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.deadlines_subject_deleted_product_variant()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text := 'product_variant';
  v_id text := old."id"::text;
  v_tenant text := old."tenant_id"::text;
begin
  if v_tenant is null then
    delete from "better_supabase"."deadlines" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."deadlines" x where x."subject_type" = v_type and x."subject_id" = v_id and x."tenant_id" = v_tenant::uuid;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_payment_term (
  id uuid
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
  select x."tenant_id" into v_tenant from "better_supabase"."payment_terms" x where x."id" = delete_payment_term.id;
  if v_tenant is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.manage'), false)) then
    raise exception 'not allowed to manage payment terms' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  delete from "better_supabase"."payment_terms" x where x."id" = delete_payment_term.id;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_team (
  team uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row jsonb;
begin
  select x."tenant_id", jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  )
    into v_tenant, v_row
    from "better_supabase"."teams" x
    where x."id" = get_team.team;
  if v_row is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.heartbeat_import_run (
  run     uuid,
  seconds integer DEFAULT 30
)
  RETURNS timestamp WITH time zone
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_until timestamptz;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role can heartbeat an import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_runs" r set "heartbeat_at" = now(), "lease_expires_at" = now() + make_interval(secs => greatest(heartbeat_import_run.seconds, 1))
  where r."id" = heartbeat_import_run.run and r."status" = 'running'
  returning r."lease_expires_at" into v_until;
  if v_until is null then
    raise exception 'the import is not running' using errcode = 'PT409', hint = 'IMPORT_RUN_NOT_RUNNING';
  end if;
  return v_until;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_ensure_ref (
  tenant   uuid,
  kind     text,
  key      text,
  defaults jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_created boolean := false;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role can ensure an import ref' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if import_ensure_ref.kind is null or import_ensure_ref.key is null or import_ensure_ref.key = '' then
    raise exception 'a ref needs a kind and a key' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select r."id" into v_id from "better_supabase".import_refs r
  where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
  if v_id is null then
    insert into "better_supabase".import_refs ("tenant_id", "kind", "key", "payload")
    values (import_ensure_ref.tenant, import_ensure_ref.kind, import_ensure_ref.key, coalesce(import_ensure_ref.defaults, '{}'::jsonb))
    on conflict ("tenant_id", "kind", "key") do nothing
    returning "id" into v_id;
    v_created := v_id is not null;
    if v_id is null then
      select r."id" into v_id from "better_supabase".import_refs r
      where r."tenant_id" = import_ensure_ref.tenant and r."kind" = import_ensure_ref.kind and lower(r."key") = lower(import_ensure_ref.key);
    end if;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'created', v_created,
    'warnings', case when v_created then jsonb_build_array(jsonb_build_object('code', 'IMPORT_REF_CREATED', 'kind', import_ensure_ref.kind, 'key', import_ensure_ref.key)) else '[]'::jsonb end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_integrity (
  tenant uuid,
  source text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_checks jsonb := '[]'::jsonb;
  v_name text;
  v_severity text;
  v_count integer;
  v_ids jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', import_integrity.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to check this import' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  for v_name, v_severity, v_count, v_ids in
    select 'duplicate_keys', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select min(d."id"::text) as sample from "better_supabase"."import_records" d
      where d."tenant_id" = import_integrity.tenant
        and (import_integrity.source is null or d."source" = import_integrity.source)
      group by d."entity", d."external_key"
      having count(distinct d."subject_id") > 1
    ) q
    union all
    select 'unbalanced_ledger', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select e."transaction_id"::text as sample from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where y."tenant_id" = import_integrity.tenant
      group by e."transaction_id"
      having sum(e."amount") <> 0
    ) q
    union all
    select 'negative_invoice', 'warning', count(*)::integer, coalesce(jsonb_agg("id"::text), '[]'::jsonb) from "better_supabase"."invoices" where "tenant_id" = import_integrity.tenant and "total" < 0 and "kind"::text is distinct from 'credit_note'
    union all
    select 'issued_without_number', 'warning', count(*)::integer, coalesce(jsonb_agg("id"::text), '[]'::jsonb) from "better_supabase"."invoices" where "tenant_id" = import_integrity.tenant and "status"::text in ('issued', 'partially_paid', 'paid') and nullif("identifier"::text, '') is null
    union all
    select 'archived_without_date', 'warning', count(*)::integer, coalesce(jsonb_agg("id"::text), '[]'::jsonb) from "better_supabase"."companies" where "tenant_id" = import_integrity.tenant and "lifecycle"::text = 'archived' and "archived_at" is null
  loop
    v_checks := v_checks || jsonb_build_array(jsonb_build_object(
      'name', v_name, 'severity', v_severity, 'count', v_count, 'ids', coalesce(v_ids, '[]'::jsonb)));
  end loop;
  return jsonb_build_object('checks', v_checks);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_import_issues (
  run        uuid,
  entity     text    DEFAULT NULL::text,
  row_limit  integer DEFAULT 50,
  row_offset integer DEFAULT 0,
  after      text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_limit integer := least(greatest(coalesce(list_import_issues.row_limit, 50), 1), 200);
  v_after_at timestamptz;
  v_after_id uuid;
  v_total integer;
  v_rows jsonb;
  v_next text;
  v_found integer;
begin
  select r."tenant_id" into v_tenant from "better_supabase"."import_runs" r where r."id" = list_import_issues.run;
  if v_tenant is null then
    raise exception 'import not found' using errcode = 'P0002', hint = 'IMPORT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to list import issues' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if list_import_issues.after is not null then
    begin
      v_after_at := split_part(convert_from(decode(translate(list_import_issues.after, '-_.', '+/='), 'base64'), 'utf8'), '|', 1)::timestamptz;
      v_after_id := split_part(convert_from(decode(translate(list_import_issues.after, '-_.', '+/='), 'base64'), 'utf8'), '|', 2)::uuid;
    exception when others then
      raise exception 'after is not a cursor of this list' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end;
  else
    select count(*) into v_total from (
      select 1 from "better_supabase".import_run_issues i
      where i."run_id" = list_import_issues.run
        and (list_import_issues.entity is null or i."entity" = list_import_issues.entity)
      limit 10001
    ) c;
  end if;
  select coalesce(jsonb_agg(to_jsonb(t) - 'id' - 'n' order by t."created_at", t."id") filter (where t."n" <= v_limit), '[]'::jsonb),
    count(*),
    max(translate(encode(convert_to(t."created_at"::text || '|' || t."id"::text, 'utf8'), 'base64'), '+/=', '-_.')) filter (where t."n" = v_limit)
  into v_rows, v_found, v_next
  from (
    select p.*, row_number() over (order by p."created_at", p."id") as "n"
    from (
      select i."id", i."entity", i."key", i."kind", i."code", i."message", i."created_at", i."resolved_at"
      from "better_supabase".import_run_issues i
      where i."run_id" = list_import_issues.run
        and (list_import_issues.entity is null or i."entity" = list_import_issues.entity)
        and (v_after_at is null or (i."created_at", i."id") > (v_after_at, v_after_id))
      order by i."created_at", i."id"
      limit v_limit + 1
      offset case when list_import_issues.after is null then greatest(coalesce(list_import_issues.row_offset, 0), 0) else 0 end
    ) p
  ) t;
  return jsonb_build_object(
    'rows', v_rows,
    'total', case when v_total is null then null else least(v_total, 10000) end,
    'capped', coalesce(v_total > 10000, false),
    'next_cursor', case when v_found > v_limit then v_next else null end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_notification_suppressions (
  max_items integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'channel', s."channel",
    'address', s."address",
    'user_id', s."user_id",
    'reason', s."reason",
    'provider', s."provider",
    'created_at', s."created_at"
  ) order by s."created_at" desc), '[]')
  from (
    select * from "better_supabase"."notification_suppressions" s
    where s."user_id" = (select auth.uid()) or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    order by s."created_at" desc
    limit least(greatest(coalesce(max_items, 50), 1), 200)
  ) s
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_teams (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_teams.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_teams.tenant, 'teams.read'), false)) then
    raise exception 'not allowed to read teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'TEAM_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text end) as v
      from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'createdAt') then
    raise exception 'sort is one of name, createdAt' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', x."id",
    'name', x."name",
    'slug', x."slug",
    'description', x."description",
    'status', x."status",
    'member_ids', coalesce((
      select jsonb_agg(m."user_id" order by m."created_at") filter (where m."user_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb),
    'member_employee_ids', coalesce((
      select jsonb_agg(m."employee_id" order by m."created_at") filter (where m."employee_id" is not null)
      from "better_supabase"."team_members" m
      where m."team_id" = x."id"
    ), '[]'::jsonb)
  ) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."teams" x
      where x."tenant_id" = list_teams.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x."status")::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."name" ilike v_search or x."slug" ilike v_search or coalesce(x."description", '') ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.merge_companies (
  keep uuid,
  drop uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_keep "better_supabase"."companies";
  v_drop "better_supabase"."companies";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_keep from "better_supabase"."companies" x where x."id" = merge_companies.keep for update;
  select * into v_drop from "better_supabase"."companies" x where x."id" = merge_companies.drop for update;
  if v_keep."id" is null or v_drop."id" is null then
    raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if v_keep."tenant_id" <> v_drop."tenant_id" or v_keep."id" = v_drop."id" or v_drop."merged_into" is not null then
    raise exception 'merge two different, unmerged records of one organization' using errcode = '22023', hint = 'PARTY_MERGE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'contacts.manage'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  update "better_supabase"."companies" x set "domain" = null, "merged_into" = merge_companies.keep,
    "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = merge_companies.drop;
  update "better_supabase"."companies" x set "domain" = coalesce(x."domain", v_drop."domain"), "website" = coalesce(x."website", v_drop."website"), "vat_id" = coalesce(x."vat_id", v_drop."vat_id"), "legal_name" = coalesce(x."legal_name", v_drop."legal_name"), "registration_id" = coalesce(x."registration_id", v_drop."registration_id"), "phone" = coalesce(x."phone", v_drop."phone"), "owner_id" = coalesce(x."owner_id", v_drop."owner_id"), "customer_terms_id" = coalesce(x."customer_terms_id", v_drop."customer_terms_id"), "supplier_terms_id" = coalesce(x."supplier_terms_id", v_drop."supplier_terms_id"), "credit_limit" = coalesce(x."credit_limit", v_drop."credit_limit"), "credit_currency" = coalesce(x."credit_currency", v_drop."credit_currency"), "credit_block" = coalesce(x."credit_block", v_drop."credit_block"), "language" = coalesce(x."language", v_drop."language"), "supplier_status" = coalesce(x."supplier_status", v_drop."supplier_status"), "updated_at" = now()
  where x."id" = merge_companies.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", merge_companies.keep, l."person_id", l."role", false
  from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop;
  update "better_supabase"."companies" x set "roles" = array(select distinct r from unnest(x."roles" || v_drop."roles") r order by 1) where x."id" = merge_companies.keep;
  perform better_supabase.merge_subject_refs('better_supabase.companies', merge_companies.keep::text, merge_companies.drop::text);
  perform "better_supabase".emit_event('company.merged', jsonb_build_object('organizationId', v_keep."tenant_id", 'companyId', merge_companies.keep, 'name', v_keep."name", 'mergedId', merge_companies.drop), 'companies/' || merge_companies.keep::text, (v_keep."tenant_id"::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'company.merged',
    category => 'data',
    target_type => 'company',
    record_id => merge_companies.keep::text,
    target_label => v_keep."name",
    summary => 'merged ' || v_drop."name" || ' into ' || v_keep."name",
    tenant => (v_keep."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_keep."tenant_id", 'companyId', merge_companies.keep, 'name', v_keep."name", 'mergedId', merge_companies.drop)
  );
  return (select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") from "better_supabase"."companies" x where x."id" = merge_companies.keep);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.merge_people (
  keep uuid,
  drop uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_keep "better_supabase"."people";
  v_drop "better_supabase"."people";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_keep from "better_supabase"."people" x where x."id" = merge_people.keep for update;
  select * into v_drop from "better_supabase"."people" x where x."id" = merge_people.drop for update;
  if v_keep."id" is null or v_drop."id" is null then
    raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if v_keep."tenant_id" <> v_drop."tenant_id" or v_keep."id" = v_drop."id" or v_drop."merged_into" is not null then
    raise exception 'merge two different, unmerged records of one organization' using errcode = '22023', hint = 'PARTY_MERGE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'contacts.manage'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  update "better_supabase"."people" x set "email" = null, "merged_into" = merge_people.keep,
    "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = merge_people.drop;
  update "better_supabase"."people" x set "email" = coalesce(x."email", v_drop."email"), "phone" = coalesce(x."phone", v_drop."phone"), "title" = coalesce(x."title", v_drop."title"), "owner_id" = coalesce(x."owner_id", v_drop."owner_id"), "user_id" = coalesce(x."user_id", v_drop."user_id"), "customer_terms_id" = coalesce(x."customer_terms_id", v_drop."customer_terms_id"), "supplier_terms_id" = coalesce(x."supplier_terms_id", v_drop."supplier_terms_id"), "credit_limit" = coalesce(x."credit_limit", v_drop."credit_limit"), "credit_currency" = coalesce(x."credit_currency", v_drop."credit_currency"), "credit_block" = coalesce(x."credit_block", v_drop."credit_block"), "language" = coalesce(x."language", v_drop."language"), "supplier_status" = coalesce(x."supplier_status", v_drop."supplier_status"), "updated_at" = now()
  where x."id" = merge_people.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", l."company_id", merge_people.keep, l."role", false
  from "better_supabase"."company_people" l where l."person_id" = merge_people.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."person_id" = merge_people.drop;
  update "better_supabase"."people" x set "roles" = array(select distinct r from unnest(x."roles" || v_drop."roles") r order by 1) where x."id" = merge_people.keep;
  update "better_supabase"."person_identities" i set "person_id" = merge_people.keep where i."person_id" = merge_people.drop;
  update "better_supabase"."inbox_conversations" x set "contact_id" = merge_people.keep where x."contact_id" = merge_people.drop;
  update "better_supabase"."identity_links" x set "contact_id" = merge_people.keep where x."contact_id" = merge_people.drop;
  perform better_supabase.merge_subject_refs('better_supabase.people', merge_people.keep::text, merge_people.drop::text);
  perform "better_supabase".emit_event('person.merged', jsonb_build_object('organizationId', v_keep."tenant_id", 'personId', merge_people.keep, 'name', v_keep."name", 'mergedId', merge_people.drop), 'persons/' || merge_people.keep::text, (v_keep."tenant_id"::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'person.merged',
    category => 'data',
    target_type => 'person',
    record_id => merge_people.keep::text,
    target_label => v_keep."name",
    summary => 'merged ' || v_drop."name" || ' into ' || v_keep."name",
    tenant => (v_keep."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_keep."tenant_id", 'personId', merge_people.keep, 'name', v_keep."name", 'mergedId', merge_people.drop)
  );
  return (select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") from "better_supabase"."people" x where x."id" = merge_people.keep);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.prune_deadlines (
  tenant            uuid,
  subject_type      text,
  subject_id        text,
  keep_jurisdiction text    DEFAULT NULL::text,
  pending_only      boolean DEFAULT true
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (prune_deadlines.tenant is not null and coalesce(better_supabase.can('tenant', prune_deadlines.tenant, 'deadlines.write'), false))) then
    raise exception 'not allowed to prune deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."deadline_subject_readable"(prune_deadlines.subject_type, prune_deadlines.subject_id, prune_deadlines.tenant)) then
    raise exception 'not allowed to prune deadlines for this subject' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  delete from "better_supabase"."deadlines" x
  where x."tenant_id" = prune_deadlines.tenant
    and x."subject_type" = prune_deadlines.subject_type
    and x."subject_id" = prune_deadlines.subject_id
    and (not coalesce(prune_deadlines.pending_only, true) or x."state" = 'pending')
    and (prune_deadlines.keep_jurisdiction is null or x."jurisdiction" <> prune_deadlines.keep_jurisdiction);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_team (
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
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = purge_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."teams" where "id" = purge_team.team;
  perform "better_supabase".emit_event('team.purged', jsonb_build_object('organizationId', v_tenant, 'id', purge_team.team), 'teams/' || (purge_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.purged',
    category => 'membership',
    target_type => 'team',
    record_id => (purge_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', purge_team.team)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_teams (
  team_ids uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_team uuid;
  v_count integer := 0;
begin
  if coalesce(cardinality(purge_teams.team_ids), 0) > 1000 then
    raise exception 'purge at most 1000 teams in one call' using errcode = '22023', hint = 'TEAM_INVALID';
  end if;
  for v_team in select distinct x from unnest(purge_teams.team_ids) x where x is not null loop
    perform "better_supabase"."purge_team"(v_team);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rebase_import_records (
  tenant   uuid,
  source   text,
  entities text[] DEFAULT NULL::text[],
  keys     text[] DEFAULT NULL::text[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role can rebase import records' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  update "better_supabase"."import_records" x
  set "subject_imported_updated_at" = coalesce((case x."entity" when 'organization_profile' then "better_supabase"."organization_profile_updated_at"(x."subject_id") when 'supplier_item' then "better_supabase"."supplier_item_updated_at"(x."subject_id") when 'product_identifier' then "better_supabase"."product_identifier_updated_at"(x."subject_id") when 'discount_group' then "better_supabase"."discount_group_updated_at"(x."subject_id") when 'discount_rule' then "better_supabase"."discount_rule_updated_at"(x."subject_id") when 'product' then "better_supabase"."product_updated_at"(x."subject_id") when 'product_category' then "better_supabase"."product_category_updated_at"(x."subject_id") when 'stock_count' then "better_supabase"."stock_count_updated_at"(x."subject_id") when 'stock_allocation' then "better_supabase"."stock_allocation_updated_at"(x."subject_id") when 'order' then "better_supabase"."order_updated_at"(x."subject_id") when 'payment_term' then "better_supabase"."payment_term_updated_at"(x."subject_id") when 'document_delivery_preference' then "better_supabase"."document_delivery_preference_updated_at"(x."subject_id") when 'party' then "better_supabase"."party_updated_at"(x."subject_id") when 'party_contact' then "better_supabase"."party_contact_updated_at"(x."subject_id") when 'contact_method' then "better_supabase"."contact_method_updated_at"(x."subject_id") when 'party_location' then "better_supabase"."party_location_updated_at"(x."subject_id") when 'party_bank_account' then "better_supabase"."party_bank_account_updated_at"(x."subject_id") when 'quote' then "better_supabase"."quote_updated_at"(x."subject_id") when 'invoice' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'credit_note' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'open_item' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'invoice_allocation' then "better_supabase"."invoice_updated_at"(x."subject_id") when 'due_check' then "better_supabase"."due_check_updated_at"(x."subject_id") when 'asset' then "better_supabase"."asset_updated_at"(x."subject_id") when 'asset_identifier' then "better_supabase"."asset_identifier_updated_at"(x."subject_id") when 'tax_code' then "better_supabase"."tax_code_updated_at"(x."subject_id") when 'document_template' then "better_supabase"."document_template_updated_at"(x."subject_id") when 'document_text_block' then "better_supabase"."document_text_block_updated_at"(x."subject_id") when 'customer' then "public"."import_customer_updated_at"(x."subject_id") when 'customer_row' then "public"."import_customer_updated_at"(x."subject_id") else null end), x."subject_imported_updated_at"),
      "owned_hash" = coalesce((null), x."owned_hash")
  where x."tenant_id" = rebase_import_records.tenant
    and x."source" = rebase_import_records.source
    and (rebase_import_records.entities is null or x."entity" = any (rebase_import_records.entities))
    and (rebase_import_records.keys is null or x."external_key" = any (rebase_import_records.keys));
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_import_source (
  id              text,
  label_key       text,
  description_key text,
  file_types      text[],
  entities        text[],
  docs_link       text   DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'not allowed to register an import source' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  insert into "better_supabase".import_sources ("id", "label_key", "description_key", "file_types", "entities", "docs_link")
  values (register_import_source.id, register_import_source.label_key, register_import_source.description_key,
    coalesce(register_import_source.file_types, '{}'), coalesce(register_import_source.entities, '{}'), register_import_source.docs_link)
  on conflict ("id") do update set
    "label_key" = excluded."label_key",
    "description_key" = excluded."description_key",
    "file_types" = excluded."file_types",
    "entities" = excluded."entities",
    "docs_link" = excluded."docs_link";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_company_person (
  company uuid,
  person  uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_role text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select l."tenant_id", l."role" into v_tenant, v_role from "better_supabase"."company_people" l
  where l."company_id" = remove_company_person.company and l."person_id" = remove_company_person.person;
  if v_tenant is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  delete from "better_supabase"."company_people" l where l."company_id" = remove_company_person.company and l."person_id" = remove_company_person.person;
  perform "better_supabase".emit_event('company.person_unlinked', jsonb_build_object('organizationId', v_tenant, 'companyId', remove_company_person.company, 'personId', remove_company_person.person, 'role', v_role), 'companies/' || remove_company_person.company::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_person_identity (
  identity uuid
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
  select i."tenant_id" into v_tenant from "better_supabase"."person_identities" i where i."id" = remove_person_identity.identity;
  if v_tenant is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  delete from "better_supabase"."person_identities" i where i."id" = remove_person_identity.identity;
  return true;
end;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
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

CREATE OR REPLACE FUNCTION better_supabase.resend_invitations (
  invitation_ids uuid[],
  valid_for      interval DEFAULT '7 days'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_sent jsonb := '[]'::jsonb;
begin
  if coalesce(cardinality(invitation_ids), 0) > 1000 then
    raise exception 'Resend at most 1000 invitations in one call' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  for v_id in select x from unnest(invitation_ids) with ordinality u(x, n) where x is not null group by x order by min(n) loop
    v_sent := v_sent || jsonb_build_array("better_supabase"."resend_invitation"(v_id, valid_for));
  end loop;
  return v_sent;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_import_conflict (
  tenant uuid,
  source text,
  entity text,
  key    text,
  action text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_resolved integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', resolve_import_conflict.tenant, 'imports.manage'), false)) then
    raise exception 'not allowed to resolve an import conflict' using errcode = '42501', hint = 'IMPORT_FORBIDDEN';
  end if;
  if resolve_import_conflict.action = 'keep' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = now()
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  elsif resolve_import_conflict.action = 'overwrite' then
    update "better_supabase"."import_records" x set "subject_imported_updated_at" = null, "owned_hash" = null
    where x."tenant_id" = resolve_import_conflict.tenant
      and x."source" = resolve_import_conflict.source
      and x."entity" = resolve_import_conflict.entity
      and x."external_key" = resolve_import_conflict.key;
  else
    raise exception 'action must be keep or overwrite' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  update "better_supabase".import_run_issues i set "resolved_at" = now()
  where i."tenant_id" = resolve_import_conflict.tenant
    and i."source" = resolve_import_conflict.source
    and i."entity" = resolve_import_conflict.entity
    and i."key" = resolve_import_conflict.key
    and i."kind" = 'conflict'
    and i."resolved_at" is null;
  get diagnostics v_resolved = row_count;
  return jsonb_build_object('action', resolve_import_conflict.action, 'resolved', v_resolved);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
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

CREATE OR REPLACE FUNCTION better_supabase.save_company (
  tenant  uuid,
  company uuid,
  attrs   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_company.company;
  v_created boolean := save_company.company is null;
  v_row jsonb;
  v_owner uuid;
  v_previous_owner uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_company.tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_company.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_company.attrs ? 'lifecycle' and not (save_company.attrs ->> 'lifecycle' = any ('{lead,prospect,customer,churned}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
  end if;
  if save_company.attrs ->> 'customerTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_company.attrs ->> 'customerTermsId' and pt."tenant_id" = save_company.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'supplierTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_company.attrs ->> 'supplierTermsId' and pt."tenant_id" = save_company.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditBlock' is not null and lower(trim(save_company.attrs ->> 'creditBlock')) not in ('none', 'soft', 'hard') then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'language' is not null and nullif(trim(save_company.attrs ->> 'language'), '') is not null and trim(save_company.attrs ->> 'language') !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditLimit' is not null and save_company.attrs ->> 'creditLimit' !~ '^[0-9]{1,18}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditCurrency' is not null and upper(trim(save_company.attrs ->> 'creditCurrency')) !~ '^[A-Z]{3}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ? 'creditLimit' <> save_company.attrs ? 'creditCurrency' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ? 'creditLimit' and (save_company.attrs ->> 'creditLimit' is null) <> (nullif(trim(save_company.attrs ->> 'creditCurrency'), '') is null) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_company_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using save_company.tenant, save_company.company, save_company.attrs;
    end if;
  end;
  begin
    if v_created then
      if nullif(trim(save_company.attrs ->> 'name'), '') is null then
        raise exception 'a name is required' using errcode = '23502', hint = 'PARTY_NAME_REQUIRED';
      end if;
      insert into "better_supabase"."companies" ("tenant_id", "name", "domain", "website", "vat_id", "legal_name", "registration_id", "phone", "lifecycle", "owner_id", "customer_terms_id", "supplier_terms_id", "credit_limit", "credit_currency", "credit_block", "language", "address", "created_by")
      values (save_company.tenant, nullif(trim(save_company.attrs ->> 'name'), ''), lower(nullif(trim(save_company.attrs ->> 'domain'), '')), nullif(trim(save_company.attrs ->> 'website'), ''), nullif(trim(save_company.attrs ->> 'vatId'), ''), nullif(trim(save_company.attrs ->> 'legalName'), ''), nullif(trim(save_company.attrs ->> 'registrationId'), ''), nullif(trim(save_company.attrs ->> 'phone'), ''), coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), ('{lead,prospect,customer,churned}'::text[])[1]), nullif(save_company.attrs ->> 'ownerId', '')::uuid, nullif(save_company.attrs ->> 'customerTermsId', '')::uuid, nullif(save_company.attrs ->> 'supplierTermsId', '')::uuid, nullif(trim(save_company.attrs ->> 'creditLimit'), '')::bigint, upper(nullif(trim(save_company.attrs ->> 'creditCurrency'), '')), lower(nullif(trim(save_company.attrs ->> 'creditBlock'), '')), nullif(trim(save_company.attrs ->> 'language'), ''), save_company.attrs -> 'address', auth.uid())
      returning "id", "owner_id" into v_id, v_owner;
    else
      select x."owner_id" into v_previous_owner from "better_supabase"."companies" x
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant;
      update "better_supabase"."companies" x set "name" = case when save_company.attrs ? 'name' then coalesce(nullif(trim(save_company.attrs ->> 'name'), ''), x."name") else x."name" end,
        "domain" = case when save_company.attrs ? 'domain' then lower(nullif(trim(save_company.attrs ->> 'domain'), '')) else x."domain" end,
        "website" = case when save_company.attrs ? 'website' then nullif(trim(save_company.attrs ->> 'website'), '') else x."website" end,
        "vat_id" = case when save_company.attrs ? 'vatId' then nullif(trim(save_company.attrs ->> 'vatId'), '') else x."vat_id" end,
        "legal_name" = case when save_company.attrs ? 'legalName' then nullif(trim(save_company.attrs ->> 'legalName'), '') else x."legal_name" end,
        "registration_id" = case when save_company.attrs ? 'registrationId' then nullif(trim(save_company.attrs ->> 'registrationId'), '') else x."registration_id" end,
        "phone" = case when save_company.attrs ? 'phone' then nullif(trim(save_company.attrs ->> 'phone'), '') else x."phone" end,
        "lifecycle" = case when save_company.attrs ? 'lifecycle' then coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_id" = case when save_company.attrs ? 'ownerId' then nullif(save_company.attrs ->> 'ownerId', '')::uuid else x."owner_id" end,
        "customer_terms_id" = case when save_company.attrs ? 'customerTermsId' then nullif(save_company.attrs ->> 'customerTermsId', '')::uuid else x."customer_terms_id" end,
        "supplier_terms_id" = case when save_company.attrs ? 'supplierTermsId' then nullif(save_company.attrs ->> 'supplierTermsId', '')::uuid else x."supplier_terms_id" end,
        "credit_limit" = case when save_company.attrs ? 'creditLimit' then nullif(trim(save_company.attrs ->> 'creditLimit'), '')::bigint else x."credit_limit" end,
        "credit_currency" = case when save_company.attrs ? 'creditCurrency' then upper(nullif(trim(save_company.attrs ->> 'creditCurrency'), '')) else x."credit_currency" end,
        "credit_block" = case when save_company.attrs ? 'creditBlock' then lower(nullif(trim(save_company.attrs ->> 'creditBlock'), '')) else x."credit_block" end,
        "language" = case when save_company.attrs ? 'language' then nullif(trim(save_company.attrs ->> 'language'), '') else x."language" end,
        "address" = case when save_company.attrs ? 'address' then save_company.attrs -> 'address' else x."address" end,
        "updated_at" = now()
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant and x."merged_into" is null
      returning x."owner_id" into v_owner;
      if not found then
        raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another company has this domain' using errcode = '23505', hint = 'PARTY_DOMAIN_TAKEN';
  end;
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") into v_row from "better_supabase"."companies" x where x."id" = v_id;
  if v_created then
    perform "better_supabase".emit_event('company.created', jsonb_build_object('organizationId', save_company.tenant, 'companyId', v_id, 'name', v_row ->> 'name'), 'companies/' || v_id::text, (save_company.tenant::text)::text, null, 'better-supabase/contacts');
  else
    perform "better_supabase".emit_event('company.updated', jsonb_build_object('organizationId', save_company.tenant, 'companyId', v_id, 'name', v_row ->> 'name'), 'companies/' || v_id::text, (save_company.tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (save_company.tenant, v_owner, 'company', v_id::text, 'participating')
    on conflict do nothing;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_company_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_payment_term (
  tenant uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_payment_term.tenant, 'contacts.manage'), false)) then
    raise exception 'not allowed to manage payment terms' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  return "better_supabase"."payment_term_write"(save_payment_term.tenant, save_payment_term.attrs, null);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_person (
  tenant uuid,
  person uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_person.person;
  v_created boolean := save_person.person is null;
  v_row jsonb;
  v_owner uuid;
  v_previous_owner uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_person.tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_person.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_person.attrs ? 'lifecycle' and not (save_person.attrs ->> 'lifecycle' = any ('{lead,mql,sql,opportunity,customer}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
  end if;
  if save_person.attrs ? 'mode' and coalesce(lower(trim(save_person.attrs ->> 'mode')), '') not in ('external', 'tenant') then
    raise exception 'a person is external or tenant' using errcode = '22023', hint = 'PARTY_MODE_INVALID';
  end if;
  if v_created and lower(trim(save_person.attrs ->> 'mode')) = 'tenant' and nullif(save_person.attrs ->> 'userId', '') is null then
    raise exception 'a tenant person needs a userId' using errcode = '22023', hint = 'PARTY_MODE_INVALID';
  end if;
  if save_person.attrs ->> 'customerTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_person.attrs ->> 'customerTermsId' and pt."tenant_id" = save_person.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'supplierTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_person.attrs ->> 'supplierTermsId' and pt."tenant_id" = save_person.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditBlock' is not null and lower(trim(save_person.attrs ->> 'creditBlock')) not in ('none', 'soft', 'hard') then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'language' is not null and nullif(trim(save_person.attrs ->> 'language'), '') is not null and trim(save_person.attrs ->> 'language') !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditLimit' is not null and save_person.attrs ->> 'creditLimit' !~ '^[0-9]{1,18}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditCurrency' is not null and upper(trim(save_person.attrs ->> 'creditCurrency')) !~ '^[A-Z]{3}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ? 'creditLimit' <> save_person.attrs ? 'creditCurrency' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ? 'creditLimit' and (save_person.attrs ->> 'creditLimit' is null) <> (nullif(trim(save_person.attrs ->> 'creditCurrency'), '') is null) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_person_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using save_person.tenant, save_person.person, save_person.attrs;
    end if;
  end;
  begin
    if v_created then
      if nullif(trim(save_person.attrs ->> 'name'), '') is null then
        raise exception 'a name is required' using errcode = '23502', hint = 'PARTY_NAME_REQUIRED';
      end if;
      insert into "better_supabase"."people" ("tenant_id", "name", "email", "phone", "title", "mode", "lifecycle", "owner_id", "user_id", "customer_terms_id", "supplier_terms_id", "credit_limit", "credit_currency", "credit_block", "language", "created_by")
      values (save_person.tenant, nullif(trim(save_person.attrs ->> 'name'), ''), lower(nullif(trim(save_person.attrs ->> 'email'), '')), nullif(trim(save_person.attrs ->> 'phone'), ''), nullif(trim(save_person.attrs ->> 'title'), ''), coalesce(lower(nullif(trim(save_person.attrs ->> 'mode'), '')), 'external'), coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), nullif(save_person.attrs ->> 'ownerId', '')::uuid, nullif(save_person.attrs ->> 'userId', '')::uuid, nullif(save_person.attrs ->> 'customerTermsId', '')::uuid, nullif(save_person.attrs ->> 'supplierTermsId', '')::uuid, nullif(trim(save_person.attrs ->> 'creditLimit'), '')::bigint, upper(nullif(trim(save_person.attrs ->> 'creditCurrency'), '')), lower(nullif(trim(save_person.attrs ->> 'creditBlock'), '')), nullif(trim(save_person.attrs ->> 'language'), ''), auth.uid())
      returning "id", "owner_id" into v_id, v_owner;
    else
      select x."owner_id" into v_previous_owner from "better_supabase"."people" x
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant;
      update "better_supabase"."people" x set "name" = case when save_person.attrs ? 'name' then coalesce(nullif(trim(save_person.attrs ->> 'name'), ''), x."name") else x."name" end,
        "email" = case when save_person.attrs ? 'email' then lower(nullif(trim(save_person.attrs ->> 'email'), '')) else x."email" end,
        "phone" = case when save_person.attrs ? 'phone' then nullif(trim(save_person.attrs ->> 'phone'), '') else x."phone" end,
        "title" = case when save_person.attrs ? 'title' then nullif(trim(save_person.attrs ->> 'title'), '') else x."title" end,
        "mode" = case when save_person.attrs ? 'mode' then coalesce(lower(nullif(trim(save_person.attrs ->> 'mode'), '')), x."mode") else x."mode" end,
        "lifecycle" = case when save_person.attrs ? 'lifecycle' then coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_id" = case when save_person.attrs ? 'ownerId' then nullif(save_person.attrs ->> 'ownerId', '')::uuid else x."owner_id" end,
        "user_id" = case when save_person.attrs ? 'userId' then nullif(save_person.attrs ->> 'userId', '')::uuid else x."user_id" end,
        "customer_terms_id" = case when save_person.attrs ? 'customerTermsId' then nullif(save_person.attrs ->> 'customerTermsId', '')::uuid else x."customer_terms_id" end,
        "supplier_terms_id" = case when save_person.attrs ? 'supplierTermsId' then nullif(save_person.attrs ->> 'supplierTermsId', '')::uuid else x."supplier_terms_id" end,
        "credit_limit" = case when save_person.attrs ? 'creditLimit' then nullif(trim(save_person.attrs ->> 'creditLimit'), '')::bigint else x."credit_limit" end,
        "credit_currency" = case when save_person.attrs ? 'creditCurrency' then upper(nullif(trim(save_person.attrs ->> 'creditCurrency'), '')) else x."credit_currency" end,
        "credit_block" = case when save_person.attrs ? 'creditBlock' then lower(nullif(trim(save_person.attrs ->> 'creditBlock'), '')) else x."credit_block" end,
        "language" = case when save_person.attrs ? 'language' then nullif(trim(save_person.attrs ->> 'language'), '') else x."language" end,
        "updated_at" = now()
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant and x."merged_into" is null
      returning x."owner_id" into v_owner;
      if not found then
        raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another person has this email' using errcode = '23505', hint = 'PARTY_EMAIL_TAKEN';
  end;
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") into v_row from "better_supabase"."people" x where x."id" = v_id;
  if v_created then
    perform "better_supabase".emit_event('person.created', jsonb_build_object('organizationId', save_person.tenant, 'personId', v_id, 'name', v_row ->> 'name'), 'persons/' || v_id::text, (save_person.tenant::text)::text, null, 'better-supabase/contacts');
  else
    perform "better_supabase".emit_event('person.updated', jsonb_build_object('organizationId', save_person.tenant, 'personId', v_id, 'name', v_row ->> 'name'), 'persons/' || v_id::text, (save_person.tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (save_person.tenant, v_owner, 'person', v_id::text, 'participating')
    on conflict do nothing;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_person_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_company_person (
  company    uuid,
  person     uuid,
  role       text,
  is_primary boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_role text := nullif(trim(set_company_person.role), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."companies" x
  join "better_supabase"."people" p on p."id" = set_company_person.person and p."tenant_id" = x."tenant_id"
  where x."id" = set_company_person.company;
  if v_tenant is null then
    raise exception 'company or person not found in one organization' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if coalesce(set_company_person.is_primary, false) then
    update "better_supabase"."company_people" l set "is_primary" = false
    where l."company_id" = set_company_person.company and l."person_id" <> set_company_person.person and l."is_primary";
  end if;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select x."tenant_id", set_company_person.company, set_company_person.person, v_role, coalesce(set_company_person.is_primary, false)
  from "better_supabase"."companies" x where x."id" = set_company_person.company
  on conflict ("company_id", "person_id") do update set "role" = excluded."role", "is_primary" = excluded."is_primary";
  perform "better_supabase".emit_event('company.person_linked', jsonb_build_object('organizationId', v_tenant, 'companyId', set_company_person.company, 'personId', set_company_person.person, 'role', v_role), 'companies/' || set_company_person.company::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_document_delivery_preferences (
  party uuid,
  prefs jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_kind text;
  v_tenant uuid;
  v_name text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select 'company', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."companies" x where x."id" = set_document_delivery_preferences.party and x."merged_into" is null;
  if v_kind is null then
    select 'person', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."people" x where x."id" = set_document_delivery_preferences.party and x."merged_into" is null;
  end if;
  if v_kind is null then
    raise exception 'company or person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(set_document_delivery_preferences.prefs) is distinct from 'array'
    or jsonb_array_length(set_document_delivery_preferences.prefs) > 100
    or exists (
      select 1 from jsonb_array_elements(set_document_delivery_preferences.prefs) e
      where jsonb_typeof(e) <> 'object'
        or length(coalesce(trim(e ->> 'documentType'), '')) not between 1 and 100
        or coalesce(e ->> 'channel', '') not in ('email', 'post', 'portal')
        or coalesce(e ->> 'copies', '1') !~ '^[0-9]{1,2}$'
        or coalesce(nullif(e ->> 'copies', '')::integer, 1) not between 1 and 20
        or (e ->> 'email' is not null and lower(trim(e ->> 'email')) !~ '^[^@[:space:]]+@[^@[:space:]]+$')
    ) or (
      select count(*) <> count(distinct (trim(e ->> 'documentType'), e ->> 'channel'))
      from jsonb_array_elements(set_document_delivery_preferences.prefs) e
    ) then
    raise exception 'prefs is an array of at most 100 { documentType, channel, copies, email } with a unique documentType and channel' using errcode = '22023', hint = 'DELIVERY_PREFERENCE_INVALID';
  end if;
  delete from "better_supabase"."document_delivery_preferences" x where x."party_id" = set_document_delivery_preferences.party and x."tenant_id" = v_tenant;
  insert into "better_supabase"."document_delivery_preferences" ("tenant_id", "party_id", "document_type", "channel", "copies", "email")
  select v_tenant, set_document_delivery_preferences.party, trim(e ->> 'documentType'), e ->> 'channel',
    coalesce(nullif(e ->> 'copies', '')::integer, 1), nullif(lower(trim(e ->> 'email')), '')
  from jsonb_array_elements(set_document_delivery_preferences.prefs) e;
  return "better_supabase"."list_document_delivery_preferences"(set_document_delivery_preferences.party);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_party_roles (
  party uuid,
  roles text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_kind text;
  v_tenant uuid;
  v_name text;
  v_roles text[] := array(select distinct trim(r) from unnest(coalesce(set_party_roles.roles, '{}'::text[])) r where nullif(trim(r), '') is not null order by 1);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select 'company', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."companies" x where x."id" = set_party_roles.party and x."merged_into" is null;
  if v_kind is null then
    select 'person', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."people" x where x."id" = set_party_roles.party and x."merged_into" is null;
  end if;
  if v_kind is null then
    raise exception 'company or person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if not (v_roles <@ '{customer,supplier,funder,partner}'::text[]) then
    raise exception 'unknown party role' using errcode = '22023', hint = 'PARTY_ROLES_INVALID';
  end if;
  if v_kind = 'company' then
    update "better_supabase"."companies" x set "roles" = v_roles, "updated_at" = now()
    where x."id" = set_party_roles.party and x."roles" is distinct from v_roles;
    if found then
      perform "better_supabase".emit_event('company.updated', jsonb_build_object('organizationId', v_tenant, 'companyId', set_party_roles.party, 'name', v_name), 'companies/' || set_party_roles.party::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
    end if;
  elsif v_kind = 'person' then
    update "better_supabase"."people" x set "roles" = v_roles, "updated_at" = now()
    where x."id" = set_party_roles.party and x."roles" is distinct from v_roles;
    if found then
      perform "better_supabase".emit_event('person.updated', jsonb_build_object('organizationId', v_tenant, 'personId', set_party_roles.party, 'name', v_name), 'persons/' || set_party_roles.party::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
    end if;
  end if;
  return case v_kind
    when 'company' then (select jsonb_build_object('type', 'company', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language")) from "better_supabase"."companies" x where x."id" = set_party_roles.party)
    when 'person' then (select jsonb_build_object('type', 'person', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language")) from "better_supabase"."people" x where x."id" = set_party_roles.party)
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_supplier_status (
  party  uuid,
  status text,
  reason text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_kind text;
  v_tenant uuid;
  v_name text;
  v_status text := nullif(trim(set_supplier_status.status), '');
  v_reason text := nullif(trim(set_supplier_status.reason), '');
  v_previous text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select 'company', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."companies" x where x."id" = set_supplier_status.party and x."merged_into" is null;
  if v_kind is null then
    select 'person', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."people" x where x."id" = set_supplier_status.party and x."merged_into" is null;
  end if;
  if v_kind is null then
    raise exception 'company or person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.approve_supplier'), false)) then
    raise exception 'not allowed to approve suppliers' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if v_status is not null and v_status not in ('approved', 'conditional', 'blocked') then
    raise exception 'a supplier status is approved, conditional or blocked' using errcode = '22023', hint = 'PARTY_SUPPLIER_STATUS_INVALID';
  end if;
  if length(v_reason) > 2000 then
    raise exception 'a reason has at most 2000 characters' using errcode = '22023', hint = 'PARTY_SUPPLIER_STATUS_INVALID';
  end if;
  if v_kind = 'company' then
    select x."supplier_status" into v_previous from "better_supabase"."companies" x where x."id" = set_supplier_status.party for update;
    update "better_supabase"."companies" x set "supplier_status" = v_status, "updated_at" = now()
    where x."id" = set_supplier_status.party and x."supplier_status" is distinct from v_status;
    if found then
      perform "better_supabase".emit_event('company.supplier_status_changed', jsonb_build_object('organizationId', v_tenant, 'companyId', set_supplier_status.party, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason), 'companies/' || set_supplier_status.party::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'company.supplier_status_changed',
    category => 'data',
    target_type => 'company',
    record_id => set_supplier_status.party::text,
    target_label => v_name,
    summary => 'supplier status of ' || v_name || ' set to ' || coalesce(v_status, 'none'),
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'companyId', set_supplier_status.party, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason)
  );
    end if;
  elsif v_kind = 'person' then
    select x."supplier_status" into v_previous from "better_supabase"."people" x where x."id" = set_supplier_status.party for update;
    update "better_supabase"."people" x set "supplier_status" = v_status, "updated_at" = now()
    where x."id" = set_supplier_status.party and x."supplier_status" is distinct from v_status;
    if found then
      perform "better_supabase".emit_event('person.supplier_status_changed', jsonb_build_object('organizationId', v_tenant, 'personId', set_supplier_status.party, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason), 'persons/' || set_supplier_status.party::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'person.supplier_status_changed',
    category => 'data',
    target_type => 'person',
    record_id => set_supplier_status.party::text,
    target_label => v_name,
    summary => 'supplier status of ' || v_name || ' set to ' || coalesce(v_status, 'none'),
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'personId', set_supplier_status.party, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason)
  );
    end if;
  end if;
  return case v_kind
    when 'company' then (select jsonb_build_object('type', 'company', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language")) from "better_supabase"."companies" x where x."id" = set_supplier_status.party)
    when 'person' then (select jsonb_build_object('type', 'person', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language")) from "better_supabase"."people" x where x."id" = set_supplier_status.party)
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.supplier_status_from_qualifications (
  party uuid
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_gaps jsonb;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."companies" x
  where x."id" = supplier_status_from_qualifications.party and x."merged_into" is null;
  if v_tenant is null then
    raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.read'), false)) then
    raise exception 'not allowed to read companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  v_gaps := "better_supabase"."qualification_gaps"(v_tenant, 'company', jsonb_build_object('holderId', supplier_status_from_qualifications.party::text));
  return case when exists (
    select 1 from jsonb_array_elements(v_gaps) g where g ->> 'status' in ('missing', 'expired')
  ) then 'conditional' else 'approved' end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_invitation (
  invitation_id uuid,
  invitee_email text  DEFAULT NULL::text,
  invitee_role  text  DEFAULT NULL::text,
  prefill       jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  current_invite "better_supabase"."invitations";
  updated "better_supabase"."invitations";
  tenant uuid;
  platform_current "better_supabase"."platform_invitations";
  platform_updated "better_supabase"."platform_invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if invitee_email is not null and btrim(invitee_email) = '' then
    raise exception 'The email address is empty' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  select * into current_invite from "better_supabase"."invitations" i
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  for update;
  if current_invite."id" is null then
    select * into platform_current from "better_supabase"."platform_invitations" i
    where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
    for update;
    if platform_current."id" is not null then
      if platform_current."expires_at" < now() then
        raise exception 'The invitation has expired; resend it to renew it' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
      end if;
      if not service and not (select coalesce(better_supabase.is_platform('platform.invite'), false)) then
        raise exception 'Not allowed to invite platform users' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
      end if;
      if invitee_role is not null and (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'platform' order by (r."id"::text = (invitee_role)::text) desc limit 1) is null then
        raise exception 'Unknown platform role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
      end if;
      if not service and (not better_supabase.platform_can_assign(auth.uid(), (platform_current."role")::text) or (invitee_role is not null and not better_supabase.platform_can_assign(auth.uid(), ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'platform' order by (r."id"::text = (invitee_role)::text) desc limit 1))::text))) then
        raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
      end if;
      if invitee_email is not null then
        delete from "better_supabase"."platform_invitations" i
        where lower(i."email") = lower(btrim(invitee_email))
          and i."id" <> invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
      end if;
      platform_updated := platform_current;
    if invitee_email is not null then
      platform_updated."email" := lower(btrim(invitee_email));
    end if;
    if invitee_role is not null then
      platform_updated."role" := (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'platform' order by (r."id"::text = (invitee_role)::text) desc limit 1);
    end if;
    update "better_supabase"."platform_invitations" i
    set "email" = platform_updated."email",
      "role" = platform_updated."role"
    where i."id" = invitation_id
    returning * into platform_updated;
      perform "better_supabase".emit_event('invitation.updated', jsonb_build_object('invitationId', platform_updated."id", 'organizationId', null, 'email', platform_updated."email", 'role', platform_updated."role"), 'invitations/' || platform_updated."id"::text, null, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.updated',
    category => 'membership',
    target_type => 'invitation',
    record_id => platform_updated."id"::text,
    metadata => jsonb_build_object('invitationId', platform_updated."id", 'organizationId', null, 'email', platform_updated."email", 'role', platform_updated."role")
  );
      return (jsonb_build_object(
    'id', platform_updated."id",
    'tenant', null,
    'email', platform_updated."email",
    'role', platform_updated."role",
    'expires_at', platform_updated."expires_at",
    'created_at', platform_updated."created_at",
    'invited_by', platform_updated."invited_by",
    'organization', null,
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = platform_updated."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(platform_updated."id")) - 'token';
    end if;
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if current_invite."expires_at" < now() then
    raise exception 'The invitation has expired; resend it to renew it' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  tenant := current_invite."tenant_id";
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or not exists (select 1 from "public"."organizations" o where o."id" = tenant) then
    raise exception 'The organization is not active' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invitee_role is not null and (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'tenant' order by (r."id"::text = (invitee_role)::text) desc limit 1) is null then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and (
    not better_supabase.can_assign(tenant, current_invite."role"::text)
    or (invitee_role is not null and not better_supabase.can_assign(tenant, ((select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'tenant' order by (r."id"::text = (invitee_role)::text) desc limit 1))::text))
  ) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
  end if;
  if invitee_email is not null and exists (
    select 1 from "public"."memberships" m join auth.users u on u.id = m."user_id"
    where m."organization_id" = tenant and lower(u.email) = lower(btrim(invitee_email))
  ) then
    raise exception '% is already a member', invitee_email using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
  if invitee_email is not null then
    delete from "better_supabase"."invitations" i
    where i."tenant_id" = tenant
      and lower(i."email") = lower(btrim(invitee_email))
      and i."id" <> invitation_id
      and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  end if;

  updated := current_invite;
    if invitee_email is not null then
      updated."email" := lower(btrim(invitee_email));
    end if;
    if invitee_role is not null then
      updated."role" := (select r."id" from "better_supabase"."roles" r where (r."id"::text = (invitee_role)::text or r."key" = (invitee_role)::text) and r."scope"::text = 'tenant' order by (r."id"::text = (invitee_role)::text) desc limit 1);
    end if;
    update "better_supabase"."invitations" i
    set "email" = updated."email",
      "role" = updated."role"
    where i."id" = invitation_id
    returning * into updated;
  perform "better_supabase".emit_event('invitation.updated', jsonb_build_object('invitationId', updated."id", 'organizationId', tenant::text, 'email', updated."email", 'role', updated."role"), 'invitations/' || updated."id"::text, (tenant)::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.updated',
    category => 'membership',
    target_type => 'invitation',
    record_id => updated."id"::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', updated."id", 'organizationId', tenant::text, 'email', updated."email", 'role', updated."role")
  );
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."tenant_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "public"."organizations" o where o."id" = updated."tenant_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = updated."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(updated."id")) - 'token';
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
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
  return (select jsonb_build_object('id', x."id", 'name', x."name", 'slug', x."slug", 'description', x."description", 'status', x."status") from "better_supabase"."teams" x where x."id" = update_team.team);
end;
$function$;

CREATE UNIQUE INDEX bsb_attachments_tenant_id_key ON better_supabase.attachments USING btree (tenant_id, id);

CREATE UNIQUE INDEX bsb_companies_tenant_id_key ON better_supabase.companies USING btree (tenant_id, id);

CREATE UNIQUE INDEX bsb_ledger_transactions_tenant_id_key ON better_supabase.ledger_transactions USING btree (tenant_id, id);

CREATE UNIQUE INDEX bsb_party_bank_accounts_tenant_id_key ON better_supabase.party_bank_accounts USING btree (tenant_id, id);

CREATE UNIQUE INDEX bsb_party_channels_tenant_id_key ON better_supabase.party_channels USING btree (tenant_id, id);

CREATE UNIQUE INDEX bsb_party_locations_tenant_id_key ON better_supabase.party_locations USING btree (tenant_id, id);

CREATE UNIQUE INDEX bsb_people_tenant_id_key ON better_supabase.people USING btree (tenant_id, id);

CREATE UNIQUE INDEX bsb_teams_tenant_id_key ON better_supabase.teams USING btree (tenant_id, id);

ALTER TABLE "better_supabase"."team_members"
  ADD CONSTRAINT "team_members_team_tenant_fkey" FOREIGN KEY (tenant_id, team_id) REFERENCES better_supabase.teams(tenant_id, id) ON DELETE CASCADE;

CREATE TRIGGER bsb_deadlines_product_variant_cascade
  AFTER DELETE ON better_supabase.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.deadlines_subject_deleted_product_variant();

CREATE TRIGGER bsb_deadlines_product_cascade
  AFTER DELETE ON better_supabase.products
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.deadlines_subject_deleted_product();

REVOKE ALL ON FUNCTION "api"."compute_deadlines_many"(uuid, jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."compute_deadlines_many"(uuid, jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."prune_deadlines"(uuid, text, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."prune_deadlines"(uuid, text, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_teams"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_teams"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."resend_invitations"(uuid[], interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."resend_invitations"(uuid[], interval) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."compute_deadlines_many"(uuid, jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."compute_deadlines_many"(uuid, jsonb, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."deadlines_subject_deleted_product"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."deadlines_subject_deleted_product_variant"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."import_clear_issues"(uuid, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."import_note_issue"(uuid, text, text, text, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."import_note_warnings"(uuid, text, jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."prune_deadlines"(uuid, text, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."prune_deadlines"(uuid, text, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_teams"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_teams"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resend_invitations"(uuid[], interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resend_invitations"(uuid[], interval) TO "authenticated", "service_role";
