SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.acknowledge (
  subject_type text,
  subject_id   text,
  version_id   uuid DEFAULT NULL::uuid,
  signature_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_version uuid;
  v_row "better_supabase"."acknowledgements"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  select x."tenant_id" into v_tenant
    from "better_supabase"."acknowledgement_assignments" x
    join "public"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" in ('*', (select r."key" from "better_supabase"."roles" r where r."id" = m."role")))
      or (x."principal_type" = 'team' and exists (
        select 1 from "better_supabase"."team_members" tm
        where tm."tenant_id" = m."organization_id"
          and tm."user_id" = m."user_id"
          and tm."team_id"::text = x."principal_id"
      )))
    limit 1;
  if v_tenant is null then
    raise exception 'you aren''t asked to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) and case acknowledge.subject_type
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (acknowledge.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'compliance.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (acknowledge.subject_id)::uuid and s."tenant_id" = v_tenant and (coalesce(better_supabase.can('tenant', v_tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end) then
    raise exception 'not allowed to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledge.subject_type, acknowledge.subject_id);
  if v_version is null then
    raise exception 'the record has no version to acknowledge' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if acknowledge.version_id is not null and acknowledge.version_id <> v_version then
    raise exception 'the record has a newer version; acknowledge that one' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if acknowledge.signature_id is not null and not exists (
    select 1 from "better_supabase"."signatures" sg
    join "better_supabase"."signature_requests" sr on sr."id" = sg."request_id"
    where sg."id" = acknowledge.signature_id
      and sg."signer" = v_me
      and sr."status" = 'completed'
      and sr."tenant_id" = v_tenant
      and sr."subject_type" = acknowledge.subject_type
      and sr."subject_id" = acknowledge.subject_id
      and sr."version_id" = v_version
  ) then
    raise exception 'the signature isn''t your completed signature on this version' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_SIGNATURE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_create"(uuid, text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid, $5::uuid)', v_hook::oid::regproc)
        using v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me;
    end if;
  end;
  insert into "better_supabase"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me, case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if found then
    perform "better_supabase".emit_event('acknowledgement.created', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id"), 'acknowledgements/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/acknowledgements');
  perform better_supabase.audit_event(
    event_type => 'acknowledgement.created',
    category => 'data',
    target_type => 'acknowledgement',
    record_id => v_row."id"::text,
    summary => 'acknowledged ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id")
  );
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    select * into v_row from "better_supabase"."acknowledgements" x
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and x."version_id" = v_version and x."user_id" = v_me;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.acknowledgement_status (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1)
  );
  v_version uuid;
  v_created timestamptz;
begin
  if v_tenant is null then
    return jsonb_build_object('versionId', null, 'required', 0, 'acknowledged', 0, 'pending', '[]'::jsonb);
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and case acknowledgement_status.subject_type
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (acknowledgement_status.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'compliance.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (acknowledgement_status.subject_id)::uuid and s."tenant_id" = v_tenant and (coalesce(better_supabase.can('tenant', v_tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgement_status.subject_type, acknowledgement_status.subject_id);
  select x."created_at" into v_created from "better_supabase"."versions" x where x."id" = v_version;
  return (
    select jsonb_build_object(
      'versionId', v_version,
      'required', count(*),
      'acknowledged', count(k."id"),
      'pending', coalesce(jsonb_agg(jsonb_build_object(
        'userId', c.user_id,
        'dueOn', (v_created)::date + c.due_in_days,
        'overdue', coalesce((v_created)::date + c.due_in_days < current_date, false)
      ) order by (v_created)::date + c.due_in_days nulls last, c.user_id) filter (where k."id" is null), '[]'::jsonb)
    )
    from (select m."user_id" as user_id, min(x."due_in_days") as due_in_days
      from "better_supabase"."acknowledgement_assignments" x
      join "public"."memberships" m on m."organization_id" = x."tenant_id"
      where x."tenant_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id
        and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" in ('*', (select r."key" from "better_supabase"."roles" r where r."id" = m."role")))
      or (x."principal_type" = 'team' and exists (
        select 1 from "better_supabase"."team_members" tm
        where tm."tenant_id" = m."organization_id"
          and tm."user_id" = m."user_id"
          and tm."team_id"::text = x."principal_id"
      )))
      group by m."user_id") c
    left join "better_supabase"."acknowledgements" k on k."subject_type" = acknowledgement_status.subject_type and k."subject_id" = acknowledgement_status.subject_id
      and k."version_id" = v_version and k."user_id" = c.user_id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_compliance_policy (
  policy_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."compliance_policies"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."compliance_policies" x where x."id" = archive_compliance_policy.policy_id for update;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  update "better_supabase"."compliance_policies" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase"."drop_acknowledgement_assignment"(v_row."tenant_id", 'compliance_policy', v_row."id"::text, 'role', '*');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.assign_acknowledgement (
  tenant         uuid,
  subject_type   text,
  subject_id     text,
  principal_type text,
  principal_id   text,
  due_in_days    integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_assignment jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false) and case assign_acknowledgement.subject_type
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (assign_acknowledgement.subject_id)::uuid and s."tenant_id" = assign_acknowledgement.tenant) and coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'compliance.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (assign_acknowledgement.subject_id)::uuid and s."tenant_id" = assign_acknowledgement.tenant and (coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end)) then
    raise exception 'not allowed to assign acknowledgements on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if assign_acknowledgement.subject_type not in ('compliance_policy', 'drive_node') then
    raise exception 'blocks.acknowledgements.on does not allow this record type' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_SUBJECT_UNSUPPORTED';
  end if;
  if assign_acknowledgement.due_in_days is not null and (assign_acknowledgement.due_in_days < 1 or assign_acknowledgement.due_in_days > 365) then
    raise exception 'due_in_days must be between 1 and 365' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_DUE_INVALID';
  end if;
  if assign_acknowledgement.principal_type = 'user' then
    if not exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = assign_acknowledgement.tenant and m."user_id"::text = assign_acknowledgement.principal_id
    ) then
      raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  elsif assign_acknowledgement.principal_type = 'team' then
    if not exists (
      select 1 from "better_supabase"."teams" t
      where t."id"::text = assign_acknowledgement.principal_id
        and t."tenant_id" = assign_acknowledgement.tenant
    ) then
      raise exception 'the team isn''t a team in this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  elsif assign_acknowledgement.principal_type = 'role' then
    if not (assign_acknowledgement.principal_id = '*'
      or assign_acknowledgement.principal_id = any (array['owner', 'admin', 'member', 'viewer']::text[])
      or exists (select 1 from "public"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = assign_acknowledgement.principal_id)) then
      raise exception 'the role isn''t a role in this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  else
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_assignment_create"(uuid, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text)', v_hook::oid::regproc)
        using assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id;
    end if;
  end;
  v_assignment := "better_supabase"."place_acknowledgement_assignment"(
    assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id,
    assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_assignment ->> 'id')::uuid;
    end if;
  end;
  return v_assignment;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_my_acknowledgements (
  tenant       uuid,
  pending_only boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null or not exists (
    select 1 from "public"."memberships" m where m."organization_id" = list_my_acknowledgements.tenant and m."user_id" = v_me
  ) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'organizationId', list_my_acknowledgements.tenant,
      'subjectType', z.subject_type,
      'subjectId', z.subject_id,
      'subjectTitle', "better_supabase"."subject_title"(z.subject_type, z.subject_id),
      'versionId', z.version_id,
      'dueOn', z.due_on,
      'overdue', k."id" is null and z.due_on is not null and z.due_on < current_date,
      'acknowledgedAt', k."acknowledged_at"
    ) order by k."id" is not null, z.due_on nulls last, z.subject_type, z.subject_id), '[]'::jsonb)
    from (
      select y.subject_type, y.subject_id, y.version_id,
        ((select vv."created_at" from "better_supabase"."versions" vv where vv."id" = y.version_id))::date + y.due_in_days as due_on
      from (
        select q.subject_type, q.subject_id, q.due_in_days,
          "better_supabase"."current_acknowledgement_version"(list_my_acknowledgements.tenant, q.subject_type, q.subject_id) as version_id
        from (
          select x."subject_type" as subject_type, x."subject_id" as subject_id, min(x."due_in_days") as due_in_days
          from "better_supabase"."acknowledgement_assignments" x
          join "public"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
          where x."tenant_id" = list_my_acknowledgements.tenant and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" in ('*', (select r."key" from "better_supabase"."roles" r where r."id" = m."role")))
      or (x."principal_type" = 'team' and exists (
        select 1 from "better_supabase"."team_members" tm
        where tm."tenant_id" = m."organization_id"
          and tm."user_id" = m."user_id"
          and tm."team_id"::text = x."principal_id"
      )))
          group by x."subject_type", x."subject_id"
        ) q
        where case q.subject_type
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (q.subject_id)::uuid and s."tenant_id" = list_my_acknowledgements.tenant) and coalesce(better_supabase.can('tenant', list_my_acknowledgements.tenant, 'compliance.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (q.subject_id)::uuid and s."tenant_id" = list_my_acknowledgements.tenant and (coalesce(better_supabase.can('tenant', list_my_acknowledgements.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end
      ) y
      where y.version_id is not null
    ) z
    left join "better_supabase"."acknowledgements" k on k."subject_type" = z.subject_type and k."subject_id" = z.subject_id
      and k."version_id" = z.version_id and k."user_id" = v_me
    where not coalesce(list_my_acknowledgements.pending_only, true) or k."id" is null
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify_due_acknowledgements()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_item record;
  v_claims text;
  v_count integer := 0;
begin
  for v_item in
    select y.tenant, y.subject_type, y.subject_id, y.version_id, y.user_id,
      (vv."created_at")::date + y.due_in_days as due_on
    from (
      select q.*, "better_supabase"."current_acknowledgement_version"(q.tenant, q.subject_type, q.subject_id) as version_id
      from (
        select x."tenant_id" as tenant, x."subject_type" as subject_type, x."subject_id" as subject_id,
          m."user_id" as user_id, min(x."due_in_days") as due_in_days
        from "better_supabase"."acknowledgement_assignments" x
        join "public"."memberships" m on m."organization_id" = x."tenant_id"
        where x."due_in_days" is not null and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" in ('*', (select r."key" from "better_supabase"."roles" r where r."id" = m."role")))
      or (x."principal_type" = 'team' and exists (
        select 1 from "better_supabase"."team_members" tm
        where tm."tenant_id" = m."organization_id"
          and tm."user_id" = m."user_id"
          and tm."team_id"::text = x."principal_id"
      )))
        group by x."tenant_id", x."subject_type", x."subject_id", m."user_id"
      ) q
    ) y
    join "better_supabase"."versions" vv on vv."id" = y.version_id
    where (vv."created_at")::date + y.due_in_days < current_date
      and not exists (
        select 1 from "better_supabase"."acknowledgements" k
        where k."subject_type" = y.subject_type and k."subject_id" = y.subject_id
          and k."version_id" = y.version_id and k."user_id" = y.user_id
      )
      and not exists (
        select 1 from "better_supabase"."acknowledgement_notices" nt
        where nt."subject_type" = y.subject_type and nt."subject_id" = y.subject_id
          and nt."version_id" = y.version_id and nt."user_id" = y.user_id
      )
  loop
    insert into "better_supabase"."acknowledgement_notices" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id")
    values (v_item.tenant, v_item.subject_type, v_item.subject_id, v_item.version_id, v_item.user_id)
    on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing;
    if found then
      perform "better_supabase".emit_event('acknowledgement.reminded', jsonb_build_object('organizationId', v_item.tenant, 'subjectType', v_item.subject_type, 'subjectId', v_item.subject_id, 'versionId', v_item.version_id, 'userId', v_item.user_id, 'dueOn', v_item.due_on), 'acknowledgements/' || v_item.subject_type || '/' || v_item.subject_id, (v_item.tenant)::text, null, 'better-supabase/acknowledgements');
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'acknowledgement.reminded',
      'tenant', v_item.tenant,
      'actor', null,
      'subject_type', v_item.subject_type,
      'subject_id', v_item.subject_id,
      'summary', coalesce("better_supabase"."subject_title"(v_item.subject_type, v_item.subject_id), v_item.subject_type),
      'recipients', to_jsonb(array[v_item.user_id]),
      'key', 'acknowledgement.reminded:' || v_item.subject_type || ':' || v_item.subject_id || ':' || v_item.version_id::text || ':' || v_item.user_id::text,
      'data', jsonb_build_object('versionId', v_item.version_id, 'dueOn', v_item.due_on)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_compliance_policy (
  tenant                   uuid,
  key                      text,
  title                    text,
  owner_id                 uuid    DEFAULT NULL::uuid,
  requires_acknowledgement boolean DEFAULT true,
  policy_id                uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."compliance_policies"%rowtype;
  v_required boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_compliance_policy.tenant, 'compliance.manage'), false)) then
    raise exception 'not allowed to manage policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if save_compliance_policy.owner_id is not null and not exists (
    select 1 from "public"."memberships" m where m."organization_id" = save_compliance_policy.tenant and m."user_id" = save_compliance_policy.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select x."requires_acknowledgement" and x."archived_at" is null into v_required from "better_supabase"."compliance_policies" x
    where x."tenant_id" = save_compliance_policy.tenant
      and (x."id" = save_compliance_policy.policy_id or (save_compliance_policy.policy_id is null and x."key" = save_compliance_policy.key));
  if save_compliance_policy.policy_id is null then
    insert into "better_supabase"."compliance_policies" ("tenant_id", "key", "title", "owner_id", "requires_acknowledgement")
    values (save_compliance_policy.tenant, save_compliance_policy.key, trim(save_compliance_policy.title), save_compliance_policy.owner_id, coalesce(save_compliance_policy.requires_acknowledgement, true))
    on conflict ("tenant_id", "key") do update
      set "title" = excluded."title", "owner_id" = excluded."owner_id",
        "requires_acknowledgement" = excluded."requires_acknowledgement", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."compliance_policies" x set "key" = save_compliance_policy.key, "title" = trim(save_compliance_policy.title), "owner_id" = save_compliance_policy.owner_id,
      "requires_acknowledgement" = coalesce(save_compliance_policy.requires_acknowledgement, true), "updated_at" = now()
      where x."id" = save_compliance_policy.policy_id and x."tenant_id" = save_compliance_policy.tenant
      returning * into v_row;
    if not found then
      raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
    end if;
  end if;
  if v_row."requires_acknowledgement" and v_row."archived_at" is null and v_required is distinct from true then
    perform "better_supabase"."place_acknowledgement_assignment"(v_row."tenant_id", 'compliance_policy', v_row."id"::text, 'role', '*', null);
  elsif not v_row."requires_acknowledgement" and v_required then
    perform "better_supabase"."drop_acknowledgement_assignment"(v_row."tenant_id", 'compliance_policy', v_row."id"::text, 'role', '*');
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$function$;
