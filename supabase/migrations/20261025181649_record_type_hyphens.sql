SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."assets"
  DROP CONSTRAINT "assets_assignee_type_check";

ALTER TABLE "better_supabase"."assignment_queues"
  DROP CONSTRAINT "assignment_queues_subject_type_check";

ALTER TABLE "better_supabase"."attachments"
  DROP CONSTRAINT "attachments_subject_type_check";

ALTER TABLE "better_supabase"."rule_defaults"
  DROP CONSTRAINT "rule_defaults_subject_type_check";

ALTER TABLE "better_supabase"."rule_fields"
  DROP CONSTRAINT "rule_fields_subject_type_check";

ALTER TABLE "better_supabase"."rules"
  DROP CONSTRAINT "rules_subject_type_check";

ALTER TABLE "better_supabase"."score_models"
  DROP CONSTRAINT "score_models_subject_type_check";

ALTER TABLE "better_supabase"."segments"
  DROP CONSTRAINT "segments_subject_type_check";

ALTER TABLE "better_supabase"."sequence_enrollments"
  DROP CONSTRAINT "sequence_enrollments_subject_type_check";

CREATE OR REPLACE FUNCTION better_supabase.assign_asset (
  asset_id      uuid,
  assignee_type text,
  assignee_id   text,
  note          text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."assets"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."assets" x where x."id" = assign_asset.asset_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)) or (v_row."assignee_type" = 'member' and v_row."assignee_id" = auth.uid()::text)) then
    raise exception 'asset not found' using errcode = 'P0002', hint = 'ASSETS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.assign'), false)) then
    raise exception 'not allowed to assign assets' using errcode = '42501', hint = 'ASSETS_FORBIDDEN';
  end if;
  if v_row."status" = 'retired' then
    raise exception 'a retired asset can''t be assigned' using errcode = '55000', hint = 'ASSETS_RETIRED';
  end if;
  if coalesce(assign_asset.assignee_type, '') !~ '^[a-z][a-z0-9_-]{0,62}$' or coalesce(assign_asset.assignee_id, '') = '' then
    raise exception 'an assignee needs a lowercase type and an id' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  if assign_asset.assignee_type = 'member' and (
    assign_asset.assignee_id !~ '^[0-9a-fA-F-]{36}$'
    or not coalesce(better_supabase.can_user(assign_asset.assignee_id::uuid, 'tenant', v_row."tenant_id", 'assets.read'), false)
  ) then
    raise exception 'the member can''t see this organization''s assets' using errcode = '22023', hint = 'ASSETS_ASSIGNEE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_asset_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using v_row."id", assign_asset.assignee_type, assign_asset.assignee_id;
    end if;
  end;
  update "better_supabase"."asset_assignments" y set "released_at" = now()
    where y."asset_id" = v_row."id" and y."released_at" is null;
  insert into "better_supabase"."asset_assignments" ("tenant_id", "asset_id", "assignee_type", "assignee_id", "note", "assigned_by")
  values (v_row."tenant_id", v_row."id", assign_asset.assignee_type, assign_asset.assignee_id, nullif(trim(assign_asset.note), ''), auth.uid());
  update "better_supabase"."assets" x set "assignee_type" = assign_asset.assignee_type, "assignee_id" = assign_asset.assignee_id, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('asset.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id"), 'assets/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/assets');
  perform better_supabase.audit_event(
    event_type => 'asset.assigned',
    category => 'data',
    target_type => 'asset',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'assigned asset',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'name', v_row."name", 'status', v_row."status", 'locationId', v_row."location_id", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_asset_assign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'locationId', v_row."location_id", 'kind', v_row."kind", 'name', v_row."name", 'tag', v_row."tag", 'serialNumber', v_row."serial_number", 'status', v_row."status", 'assigneeType', v_row."assignee_type", 'assigneeId', v_row."assignee_id", 'latitude', v_row."latitude", 'longitude', v_row."longitude", 'metadata', v_row."metadata", 'retiredAt', v_row."retired_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.enroll_in_sequence (
  sequence_id  uuid,
  subject_type text,
  subject_id   text,
  attrs        jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_sequence "better_supabase"."sequences";
  v_row "better_supabase"."enrollments";
  v_member "better_supabase"."sequence_enrollments";
  v_attrs jsonb := coalesce(enroll_in_sequence.attrs, '{}'::jsonb);
  v_address text;
  v_name text;
  v_email text;
  v_label text;
  v_account uuid;
  v_owner uuid;
  v_variables jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_sequence from "better_supabase"."sequences" x where x."id" = enroll_in_sequence.sequence_id;
  if v_sequence."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.enroll'), false)))) then
    raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.enroll'), false))) then
    raise exception 'not allowed to enroll in sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if v_sequence."status" <> 'active' then
    raise exception 'only an active sequence takes enrollments' using errcode = '55000', hint = 'SEQUENCE_NOT_ACTIVE';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if enroll_in_sequence.subject_type is null or enroll_in_sequence.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'subject_type: use lowercase letters, digits or _' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if enroll_in_sequence.subject_id is null or length(enroll_in_sequence.subject_id) not between 1 and 200 then
    raise exception 'subject_id must be 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  v_address := nullif(trim(v_attrs ->> 'address'), '');
  v_name := nullif(trim(v_attrs ->> 'name'), '');
  v_account := nullif(v_attrs ->> 'accountId', '')::uuid;
  v_variables := coalesce(v_attrs -> 'variables', '{}'::jsonb);
  if enroll_in_sequence.subject_type = 'person' then
    select y."email", y."name" into v_email, v_label
    from "better_supabase"."people" y
    where y."id"::text = enroll_in_sequence.subject_id and y."tenant_id" = v_sequence."tenant_id";
    if not found then
      raise exception 'no such person in this organization' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    v_address := coalesce(v_address, v_email);
    v_name := coalesce(v_name, v_label);
  end if;
  if v_address is not null and (length(v_address) > 320 or v_address !~ '^[^@[:space:]]+@[^@[:space:]]+$') then
    raise exception 'address must be an email address' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if length(v_name) > 200 then
    raise exception 'name must be at most 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if jsonb_typeof(v_variables) <> 'object' or length(v_variables::text) > 10000 then
    raise exception 'variables must be an object of at most 10000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_address is null and exists (select 1 from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'kind' = 'email') then
    raise exception 'the recipient needs an email address for the sequence''s email steps' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_account is null then
    v_account := coalesce(v_sequence."mail_account_id", (
      select k."id" from "better_supabase"."mail_accounts" k
      where k."tenant_id" = v_sequence."tenant_id" and k."user_id" = auth.uid() and k."status" = 'active'
      order by k."created_at", k."id"
      limit 1));
  else
    select k."user_id" into v_owner from "better_supabase"."mail_accounts" k
    where k."id" = v_account and k."tenant_id" = v_sequence."tenant_id" and k."status" <> 'disconnected';
    if not found then
      raise exception 'accountId must be a connected mailbox of this organization' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    if v_owner is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.manage'), false))) then
      raise exception 'only a sequence manager sends from another user''s mailbox' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
    end if;
  end if;
  if v_account is null and exists (select 1 from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'kind' = 'email') then
    raise exception 'connect a mailbox or set one on the sequence to send its email steps' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_sequence."tenant_id" and x."program" = ('sequence:' || v_sequence."id"::text)
    and x."subject_type" = enroll_in_sequence.subject_type and x."subject_id" = enroll_in_sequence.subject_id
  for update;
  if v_row."id" is not null then
    select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = v_row."id" for update;
    if v_member."status" in ('active', 'paused') then
      return "better_supabase"."sequence_member_json"(v_row."id");
    end if;
    -- Starting over: clearing the steps makes enrollment_ensure take the
    -- current ones, with none done.
    delete from "better_supabase"."enrollment_steps" x where x."enrollment_id" = v_row."id";
    update "better_supabase"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "completed_at" = null, "enrolled_by" = auth.uid(),
      "enrolled_at" = now(), "steps" = '{}'
    where x."id" = v_row."id";
  end if;
  v_id := "better_supabase"."enrollment_ensure"(v_sequence."tenant_id", ('sequence:' || v_sequence."id"::text), v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord),
    enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, auth.uid());
  insert into "better_supabase"."sequence_enrollments" ("enrollment_id", "tenant_id", "sequence_id", "subject_type", "subject_id", "address", "name",
    "mail_account_id", "variables", "enrolled_by")
  values (v_id, v_sequence."tenant_id", v_sequence."id", enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, v_address, v_name,
    v_account, v_variables, auth.uid())
  on conflict ("enrollment_id") do update
  set "address" = excluded."address", "name" = excluded."name", "mail_account_id" = excluded."mail_account_id",
    "variables" = excluded."variables", "enrolled_by" = excluded."enrolled_by", "status" = 'active',
    "exit_reason" = null, "step" = null, "next_run_at" = null, "mail_thread_id" = null, "attempts" = 0,
    "last_error" = null, "updated_at" = now();
  perform "better_supabase"."sequence_place"(v_id);
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = v_id;
  perform "better_supabase".emit_event('sequence_enrollment.created', jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', null::text, 'reason', null::text), 'sequence-enrollments/' || v_member."enrollment_id"::text, (v_member."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence_enrollment.created',
    category => 'data',
    target_type => 'sequence',
    record_id => v_member."sequence_id"::text,
    target_label => v_member."subject_type" || ':' || v_member."subject_id",
    summary => 'enrolled in a sequence',
    tenant => (v_member."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', null::text, 'reason', null::text)
  );
  return "better_supabase"."sequence_member_json"(v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.parse_mentions (
  body text
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'users', coalesce((
      select jsonb_agg(distinct lower(m[1]))
      from regexp_matches(parse_mentions.body, '@\[[^\]\n]{1,100}\]\((?:user:)?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\)', 'gi') m
    ), '[]'::jsonb),
    'subjects', coalesce((
      select jsonb_agg(distinct jsonb_build_object('type', m[1], 'id', m[2]))
      from regexp_matches(parse_mentions.body, '@\[[^\]\n]{1,100}\]\(subject:([a-z][a-z0-9_-]{0,62})/([^)\s]{1,200})\)', 'g') m
    ), '[]'::jsonb),
    'scope', case
      when parse_mentions.body ~ '(^|[^\w@])@channel\M' then 'channel'
      when parse_mentions.body ~ '(^|[^\w@])@here\M' then 'here'
    end
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_assignment_queue (
  tenant uuid,
  queue  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_old "better_supabase"."assignment_queues";
  v_row "better_supabase"."assignment_queues";
  v_type text;
  v_conditions jsonb;
  v_fields jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(better_supabase.can('tenant', save_assignment_queue.tenant, 'assignment.manage'), false) then
    raise exception 'You need assignment.manage to change assignment queues' using errcode = '42501', hint = 'ASSIGNMENT_FORBIDDEN';
  end if;
  if jsonb_typeof(queue) is distinct from 'object' then
    raise exception 'queue must be an object' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
  end if;
  v_id := nullif(queue ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."assignment_queues" x
    where x."id" = v_id and x."tenant_id" = save_assignment_queue.tenant for update;
    if v_old."id" is null then
      raise exception 'No assignment queue in this organization has this id' using errcode = 'P0002', hint = 'ASSIGNMENT_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(queue ->> 'subjectType', v_old."subject_type");
  if v_type is null or v_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'A queue needs a subject type' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
  end if;
  v_conditions := case when queue ? 'conditions' then nullif(queue -> 'conditions', 'null'::jsonb) else v_old."conditions" end;
  if v_conditions is not null then
    v_fields := "better_supabase"."rule_field_map"(v_type);
    if v_fields = '{}'::jsonb then
      raise exception 'No rule fields for this subject type; sync them first' using errcode = '22023', hint = 'ASSIGNMENT_FIELDS_MISSING';
    end if;
    perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."assignment_queues" ("tenant_id", "name", "subject_type", "strategy", "conditions", "rank", "enabled")
    values (save_assignment_queue.tenant, trim(queue ->> 'name'), v_type, coalesce(queue ->> 'strategy', 'round_robin'),
      v_conditions, coalesce((queue ->> 'rank')::integer, 0), coalesce((queue ->> 'enabled')::boolean, true))
    returning * into v_row;
  else
    update "better_supabase"."assignment_queues" x set
      "name" = coalesce(trim(queue ->> 'name'), x."name"),
      "subject_type" = v_type,
      "strategy" = coalesce(queue ->> 'strategy', x."strategy"),
      "conditions" = v_conditions,
      "rank" = coalesce((queue ->> 'rank')::integer, x."rank"),
      "enabled" = coalesce((queue ->> 'enabled')::boolean, x."enabled"),
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'subjectType', v_row."subject_type", 'strategy', v_row."strategy", 'conditions', v_row."conditions", 'rank', v_row."rank", 'enabled', v_row."enabled", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', z."user_id", 'weight', z."weight", 'active', z."active", 'assignedCount', z."assigned_count", 'lastAssignedAt', z."last_assigned_at") order by z."user_id")
      from "better_supabase"."assignment_queue_members" z where z."queue_id" = v_row."id"
    ), '[]'::jsonb));
exception
  when unique_violation then
    raise exception 'Another assignment queue in this organization has this name' using errcode = '23505', hint = 'ASSIGNMENT_NAME_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'A queue needs a name of at most 200 characters and a strategy of round_robin or weighted' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_rule (
  tenant uuid,
  rule   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."rules";
  v_row "better_supabase"."rules";
  v_subject_type text;
  v_trigger text;
  v_name text;
  v_description text;
  v_conditions jsonb;
  v_actions jsonb;
  v_enabled boolean;
  v_stop boolean;
  v_fields jsonb;
  v_action jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(rule) is distinct from 'object' then
    raise exception 'rule must be an object' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  v_id := nullif(rule ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."rules" x where x."id" = v_id and x."organization_id" = save_rule.tenant for update;
    if v_old."id" is null then
      raise exception 'No rule in this organization has this id' using errcode = 'P0002', hint = 'RULE_NOT_FOUND';
    end if;
    if rule ? 'version' and (rule ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'The rule changed since it was read' using errcode = '40001', hint = 'RULE_CONFLICT';
    end if;
    if rule ? 'subjectType' and rule ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'A rule''s subject type can''t change' using errcode = '22023', hint = 'RULE_INVALID';
    end if;
  end if;
  v_subject_type := coalesce(v_old."subject_type", rule ->> 'subjectType');
  v_trigger := coalesce(rule ->> 'trigger', v_old."trigger");
  v_name := coalesce(nullif(trim(rule ->> 'name'), ''), v_old."name");
  v_description := case when rule ? 'description' then nullif(trim(rule ->> 'description'), '') else v_old."description" end;
  v_conditions := coalesce(rule -> 'conditions', v_old."conditions", '{"id": "root", "type": "group", "combinator": "and", "rules": []}'::jsonb);
  v_actions := coalesce(rule -> 'actions', v_old."actions", '[]'::jsonb);
  v_enabled := coalesce((rule ->> 'enabled')::boolean, v_old."enabled", false);
  v_stop := coalesce((rule ->> 'stopProcessing')::boolean, v_old."stop_processing", false);
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when (v_enabled or coalesce(v_old."enabled", false)) then coalesce(better_supabase.can('tenant', save_rule.tenant, 'rules.publish'), false) else coalesce(better_supabase.can('tenant', save_rule.tenant, 'rules.edit'), false) end)) then
    raise exception 'You need % to save this rule', case when (v_enabled or coalesce(v_old."enabled", false)) then '''rules.publish''' else '''rules.edit''' end using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'A rule needs a subject type' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  if v_trigger is null or length(v_trigger) > 128 or v_trigger !~ '^[a-z][a-z0-9_]*([.:][a-z0-9_]+)*$' then
    raise exception 'A rule needs a trigger such as expense.submitted' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'A rule needs a name of at most 200 characters' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  if v_fields = '{}'::jsonb and v_old."default_key" is null then
    raise exception 'No rule fields for %; sync them first', v_subject_type using errcode = '22023', hint = 'RULE_SUBJECT_UNKNOWN';
  end if;
  perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  if jsonb_typeof(v_actions) is distinct from 'array' or jsonb_array_length(v_actions) > 20 then
    raise exception 'actions must be an array of at most 20 entries' using errcode = '22023', hint = 'RULE_ACTIONS_INVALID';
  end if;
  for v_action in select x.value from jsonb_array_elements(v_actions) x loop
    if jsonb_typeof(v_action) is distinct from 'object' or v_action ->> 'kind' is null
      or length(v_action ->> 'kind') > 128 or v_action ->> 'kind' !~ '^[a-z][a-z0-9_]*([.][a-z0-9_]+)*$'
      or (v_action ? 'config' and jsonb_typeof(v_action -> 'config') is distinct from 'object') then
      raise exception 'Every action needs a kind such as approvals.request and an optional config object' using errcode = '22023', hint = 'RULE_ACTIONS_INVALID';
    end if;
  end loop;
  if v_old."id" is null then
    insert into "better_supabase"."rules" ("organization_id", "subject_type", "trigger", "name", "description", "conditions", "actions", "enabled", "stop_processing", "rank")
    values (save_rule.tenant, v_subject_type, v_trigger, v_name, v_description, v_conditions, v_actions, v_enabled, v_stop,
      case
    when (select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type)) then (select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
    returning * into v_row;
  elsif v_old."trigger" = v_trigger and v_old."name" = v_name
    and v_old."description" is not distinct from v_description
    and v_old."conditions" = v_conditions and v_old."actions" = v_actions
    and v_old."enabled" = v_enabled and v_old."stop_processing" = v_stop then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."organization_id", 'subjectType', v_old."subject_type", 'trigger', v_old."trigger", 'name', v_old."name", 'description', v_old."description", 'conditions', v_old."conditions", 'actions', v_old."actions", 'enabled', v_old."enabled", 'stopProcessing', v_old."stop_processing", 'rank', v_old."rank", 'version', v_old."version", 'createdBy', v_old."created_by", 'updatedBy', v_old."updated_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at", 'defaultKey', v_old."default_key");
  else
    update "better_supabase"."rules" x set
      "trigger" = v_trigger,
      "name" = v_name,
      "description" = v_description,
      "conditions" = v_conditions,
      "actions" = v_actions,
      "enabled" = v_enabled,
      "stop_processing" = v_stop,
      "version" = x."version" + 1,
      "updated_by" = auth.uid(),
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."rule_versions" ("rule_id", "version", "organization_id", "name", "conditions", "actions", "saved_by")
  values (v_row."id", v_row."version", v_row."organization_id", v_row."name", v_row."conditions", v_row."actions", auth.uid())
  on conflict do nothing;
  perform "better_supabase".emit_event('rule.saved', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'rule.saved',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  if v_row."enabled" and not coalesce(v_old."enabled", false) then
    perform "better_supabase".emit_event('rule.enabled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'rule.enabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  elsif not v_row."enabled" and coalesce(v_old."enabled", false) then
    perform "better_supabase".emit_event('rule.disabled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'rule.disabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'defaultKey', v_row."default_key");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_score_model (
  tenant uuid,
  model  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."score_models";
  v_row "better_supabase"."score_models";
  v_key text;
  v_name text;
  v_description text;
  v_subject_type text;
  v_rules jsonb;
  v_metrics jsonb;
  v_bands jsonb;
  v_enabled boolean;
  v_fields jsonb;
  v_entry jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_score_model.tenant, 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if jsonb_typeof(model) is distinct from 'object' then
    raise exception 'model must be an object' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_id := nullif(model ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."score_models" x where x."id" = v_id and x."tenant_id" = save_score_model.tenant for update;
    if v_old."id" is null then
      raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
    end if;
    if model ? 'version' and (model ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the score model changed since it was read' using errcode = '40001', hint = 'SCORES_MODEL_CONFLICT';
    end if;
    if model ? 'subjectType' and model ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'a score model''s subject type can''t change' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", model ->> 'key');
  v_name := coalesce(nullif(trim(model ->> 'name'), ''), v_old."name");
  v_description := case when model ? 'description' then nullif(trim(model ->> 'description'), '') else v_old."description" end;
  v_subject_type := coalesce(v_old."subject_type", model ->> 'subjectType');
  v_rules := coalesce(model -> 'rules', v_old."rules", '[]'::jsonb);
  v_metrics := coalesce(model -> 'metrics', v_old."metrics", '[]'::jsonb);
  v_bands := coalesce(model -> 'bands', v_old."bands", '[]'::jsonb);
  v_enabled := coalesce((model ->> 'enabled')::boolean, v_old."enabled", true);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a key such as lead or health' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a score model needs a name of at most 200 characters' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_rules) is distinct from 'array' or jsonb_array_length(v_rules) > 100 then
    raise exception 'rules must be an array of at most 100 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_metrics) is distinct from 'array' or jsonb_array_length(v_metrics) > 50 then
    raise exception 'metrics must be an array of at most 50 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_bands) is distinct from 'array' or jsonb_array_length(v_bands) > 10 then
    raise exception 'bands must be an array of at most 10 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  for v_entry in select x.value from jsonb_array_elements(v_rules) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or jsonb_typeof(v_entry -> 'points') is distinct from 'number'
      or jsonb_typeof(v_entry -> 'conditions') is distinct from 'object' then
      raise exception 'every rule needs an id, conditions and a number of points' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SCORES_SUBJECT_UNKNOWN';
    end if;
    perform "better_supabase"."rule_check"(v_entry -> 'conditions', v_fields, 1);
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_metrics) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or coalesce(v_entry ->> 'source', 'field') not in ('field', 'votes')
      or (v_entry ? 'weight' and jsonb_typeof(v_entry -> 'weight') is distinct from 'number')
      or (v_entry ? 'cap' and (jsonb_typeof(v_entry -> 'cap') is distinct from 'number' or (v_entry ->> 'cap')::numeric < 0)) then
      raise exception 'every metric needs an id, a source (field or votes), and a numeric weight and cap' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if coalesce(v_entry ->> 'source', 'field') = 'field'
      and (v_fields -> (v_entry ->> 'field')) ->> 'type' is distinct from 'number' then
      raise exception 'a field metric names a number field of the subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_bands) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'label'), 0) not between 1 and 60
      or jsonb_typeof(v_entry -> 'min') is distinct from 'number' then
      raise exception 'every band needs a label and a min score' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  v_bands := coalesce((
    select jsonb_agg(jsonb_build_object('label', x.value ->> 'label', 'min', (x.value ->> 'min')::numeric) order by (x.value ->> 'min')::numeric desc)
    from jsonb_array_elements(v_bands) x
  ), '[]'::jsonb);
  if v_old."id" is null then
    if exists (select 1 from "better_supabase"."score_models" x where x."tenant_id" = save_score_model.tenant and x."key" = v_key) then
      raise exception 'a score model with this key already exists' using errcode = '23505', hint = 'SCORES_MODEL_KEY_TAKEN';
    end if;
    insert into "better_supabase"."score_models" ("tenant_id", "key", "name", "description", "subject_type", "rules", "metrics", "bands", "enabled", "created_by")
    values (save_score_model.tenant, v_key, v_name, v_description, v_subject_type, v_rules, v_metrics, v_bands, v_enabled, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."rules" = v_rules and v_old."metrics" = v_metrics
    and v_old."bands" = v_bands and v_old."enabled" = v_enabled then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'key', v_old."key", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'rules', v_old."rules", 'metrics', v_old."metrics", 'bands', v_old."bands", 'enabled', v_old."enabled", 'version', v_old."version", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at");
  else
    update "better_supabase"."score_models" x set
      "name" = v_name,
      "description" = v_description,
      "rules" = v_rules,
      "metrics" = v_metrics,
      "bands" = v_bands,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."rules" = v_rules and x."metrics" = v_metrics and x."bands" = v_bands then 0 else 1 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."score_model_versions" ("model_id", "version", "tenant_id", "rules", "metrics", "bands", "saved_by")
  values (v_row."id", v_row."version", v_row."tenant_id", v_row."rules", v_row."metrics", v_row."bands", auth.uid())
  on conflict do nothing;
  perform "better_supabase".emit_event('score_model.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.saved',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'saved score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_presence_allowed (
  topic text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_parts text[] := regexp_match(subject_presence_allowed.topic, '^presence:([a-z][a-z0-9_-]{0,62}):([^:]{1,200})$');
begin
  if v_parts is null then
    return false;
  end if;
  return coalesce("better_supabase"."can_subject"(v_parts[1], v_parts[2], 'read'), false);
exception
  when invalid_text_representation then
    return false;
end;
$function$;

ALTER TABLE "better_supabase"."assets"
  ADD CONSTRAINT "assets_assignee_type_check" CHECK (((assignee_type IS NULL) OR (assignee_type ~ '^[a-z][a-z0-9_-]{0,62}$'::text)));

ALTER TABLE "better_supabase"."assignment_queues"
  ADD CONSTRAINT "assignment_queues_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_-]{0,62}$'::text));

ALTER TABLE "better_supabase"."attachments"
  ADD CONSTRAINT "attachments_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_-]{0,62}$'::text));

ALTER TABLE "better_supabase"."rule_defaults"
  ADD CONSTRAINT "rule_defaults_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_-]{0,62}$'::text));

ALTER TABLE "better_supabase"."rule_fields"
  ADD CONSTRAINT "rule_fields_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_-]{0,62}$'::text));

ALTER TABLE "better_supabase"."rules"
  ADD CONSTRAINT "rules_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_-]{0,62}$'::text));

ALTER TABLE "better_supabase"."score_models"
  ADD CONSTRAINT "score_models_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_-]{0,62}$'::text));

ALTER TABLE "better_supabase"."segments"
  ADD CONSTRAINT "segments_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_-]{0,62}$'::text));

ALTER TABLE "better_supabase"."sequence_enrollments"
  ADD CONSTRAINT "sequence_enrollments_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_-]{0,62}$'::text));
