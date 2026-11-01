SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.assign_comment (
  message  uuid,
  assignee uuid  DEFAULT NULL::uuid,
  attrs    jsonb DEFAULT '{}'::jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_msg record;
  v_task uuid;
begin
  select * into v_msg from "better_supabase"."messages" x
  where x."id" = assign_comment.message and x."sent_at" is not null and x."deleted_at" is null;
  if not found then
    raise exception 'no comment you can read has this id' using errcode = 'P0002', hint = 'COMMENT_NOT_FOUND';
  end if;
  select t."task_id" into v_task from "better_supabase"."comment_tasks" t where t."message_id" = v_msg."id";
  if found then
    return v_task;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_comment_assign"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using assign_comment.message, assign_comment.assignee;
    end if;
  end;
  v_task := ("better_supabase"."create_work_item"(
    v_msg."tenant_id",
    (coalesce(assign_comment.attrs, '{}') - 'title') || jsonb_build_object(
      'title', coalesce(nullif(trim(assign_comment.attrs ->> 'title'), ''), left(v_msg."body", 120)),
      'body', coalesce(assign_comment.attrs ->> 'body', v_msg."body")
    ),
    case when assign_comment.assignee is null then '{}'::uuid[] else array[assign_comment.assignee] end
  ) ->> 'id')::uuid;
  insert into "better_supabase"."comment_tasks" ("message_id", "organization_id", "task_id")
  values (v_msg."id", v_msg."tenant_id", v_task);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_comment_assign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_task;
    end if;
  end;
  return v_task;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.assign_conversation (
  conversation uuid,
  assignee     uuid,
  team         uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_before uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = assign_conversation.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.assign'), false) or (coalesce(assignee = (select auth.uid()), false) and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false))) then
    raise exception 'not allowed to assign this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if assignee is not null and not coalesce(better_supabase.can_user(assignee, 'tenant', v_conv."tenant_id", 'inbox.read'), false) then
    raise exception 'the assignee cannot read this inbox' using errcode = '22023', hint = 'INBOX_ASSIGNEE_INVALID';
  end if;
  v_before := v_conv."assignee_id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inbox_conversation_assign"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_conv."id", assign_conversation.assignee, assign_conversation.team;
    end if;
  end;
  update "better_supabase"."inbox_conversations" set
    "assignee_id" = assign_conversation.assignee,
    "team_id" = coalesce(assign_conversation.team, "team_id")
  where "id" = v_conv."id"
  returning * into v_conv;
  if v_before is distinct from assignee then
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'assigned', (select auth.uid()), jsonb_build_object('from', v_before, 'to', assign_conversation.assignee));
    perform "better_supabase".emit_event('inbox_conversation.assigned', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status", 'previousAssigneeId', v_before), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    if assignee is not null then
      insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_conv."id", v_conv."tenant_id", assign_conversation.assignee)
    on conflict do nothing;
    end if;
    if assignee is not null and assignee is distinct from (select auth.uid()) then
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inbox.assigned',
        'tenant', v_conv."tenant_id",
        'actor', (select auth.uid()),
        'subject_type', 'conversation',
        'subject_id', v_conv."id"::text,
        'summary', v_conv."subject",
        'recipients', to_jsonb(array[assignee]),
        'key', 'inbox.assigned:' || v_conv."id"::text || ':' || assignee::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('conversationId', v_conv."id")
      ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
      null;
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inbox_conversation_assign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_conv."id";
    end if;
  end;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_enrollment (
  enrollment_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."enrollments" x where x."id" = cancel_enrollment.enrollment_id for update;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.read'), false))) or (v_row."user_id" is not null and coalesce(v_row."user_id" = auth.uid(), false))) then
    raise exception 'enrollment not found' using errcode = 'P0002', hint = 'ENROLLMENTS_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'enrollments.enroll'), false))) or (v_row."user_id" is not null and coalesce(v_row."user_id" = auth.uid(), false))) then
    raise exception 'not allowed to change this enrollment' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if position(':' in v_row."program") > 0 then
    raise exception 'this enrollment belongs to a module and can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_row."status" = 'completed' then
    raise exception 'a completed enrollment can''t be cancelled' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_enrollment_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using cancel_enrollment.enrollment_id;
    end if;
  end;
  if v_row."status" = 'active' then
    update "better_supabase"."enrollments" x
    set "status" = 'cancelled', "cancelled_at" = now(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('enrollment.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'program', v_row."program", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'step', null::text, 'completedSteps', v_row."completed_steps", 'totalSteps', cardinality(v_row."steps"), 'reason', null::text), 'enrollments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_enrollment_cancel"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using cancel_enrollment.enrollment_id;
    end if;
  end;
  return "better_supabase"."enrollment_json"(v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_comment (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  body         text,
  attrs        jsonb  DEFAULT '{}'::jsonb,
  attachments  uuid[] DEFAULT '{}'::uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv uuid;
  v_raw uuid[];
  v_mentions uuid[];
  v_msg jsonb;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_comment_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using create_comment.tenant, create_comment.subject_type, create_comment.subject_id, create_comment.body;
    end if;
  end;
  v_conv := ("better_supabase"."open_conversation"(
    create_comment.tenant,
    'subject',
    jsonb_build_object('subjectType', create_comment.subject_type, 'subjectId', create_comment.subject_id),
    '{}'::uuid[]
  ) ->> 'id')::uuid;
  v_raw := array(
    select (jsonb_array_elements_text(coalesce(create_comment.attrs -> 'mentions', '[]'::jsonb)))::uuid
  );
  v_mentions := array(select distinct e.x from (
    select x from unnest(v_raw) x
  ) e(x) where e.x is not null);
  v_msg := "better_supabase"."send_message"(
    v_conv,
    create_comment.body,
    (coalesce(create_comment.attrs, '{}') - 'mentions' - 'broadcast' - 'scheduledFor') || jsonb_build_object('mentions', to_jsonb(v_mentions)),
    coalesce(create_comment.attachments, '{}')
  );
  perform "better_supabase"."comment_sent"((v_msg ->> 'id')::uuid);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_comment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using (v_msg ->> 'id')::uuid;
    end if;
  end;
  return "better_supabase"."comments_json"(array[(v_msg ->> 'id')::uuid]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_workflow_schedule (
  name     text,
  workflow text,
  cron     text,
  next_run timestamp with time zone,
  payload  jsonb                    DEFAULT '{}'::jsonb,
  timezone text                     DEFAULT 'UTC'::text,
  tenant   uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_schedules"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflows.manage'), false))) then
    raise exception 'You may not schedule workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_workflow_schedule_create"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using name, workflow, tenant;
    end if;
  end;
  insert into "better_supabase"."workflow_schedules" as x ("tenant_id", "name", "workflow", "input", "cron", "timezone", "next_run_at", "created_by")
  values (tenant, name, workflow, coalesce(payload -> 'input', '[]'::jsonb), cron, coalesce(timezone, 'UTC'), next_run, (select auth.uid()))
  on conflict on constraint workflow_schedules_tenant_name_key do update set
    "workflow" = excluded."workflow",
    "input" = excluded."input",
    "cron" = excluded."cron",
    "timezone" = excluded."timezone",
    "next_run_at" = excluded."next_run_at",
    "locked_until" = null
  returning * into v_row;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_workflow_schedule_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'name', v_row."name",
    'workflow', v_row."workflow",
    'input', v_row."input",
    'cron', v_row."cron",
    'timezone', v_row."timezone",
    'nextRunAt', v_row."next_run_at",
    'lastRunAt', v_row."last_run_at",
    'paused', v_row."paused",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.enroll (
  tenant       uuid,
  program      text,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_program "better_supabase"."enrollment_programs";
  v_row "better_supabase"."enrollments";
  v_id uuid;
  v_steps text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (enroll.tenant is not null and coalesce(better_supabase.can('tenant', enroll.tenant, 'enrollments.enroll'), false))) then
    raise exception 'not allowed to enroll' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  select * into v_program from "better_supabase"."enrollment_programs" x
  where x."tenant_id" = enroll.tenant and x."key" = enroll.program;
  if v_program."id" is null then
    raise exception 'enrollment program not found' using errcode = 'P0002', hint = 'ENROLLMENTS_PROGRAM_NOT_FOUND';
  end if;
  if not v_program."enabled" then
    raise exception 'this program is turned off' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type is null or enroll.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' or enroll.subject_id is null or length(enroll.subject_id) not between 1 and 200 then
    raise exception 'an enrollment needs a subject type and id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if cardinality(v_program."subject_types") > 0 and not (enroll.subject_type = any(v_program."subject_types")) then
    raise exception 'this program doesn''t enroll this subject type' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if enroll.subject_type = 'user' and enroll.subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'a user subject needs a user id' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  v_steps := array(select t.value ->> 'id' from jsonb_array_elements(v_program."steps") with ordinality as t(value, ord) order by t.ord);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_enrollment_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using enroll.tenant, enroll.program, enroll.subject_type, enroll.subject_id;
    end if;
  end;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = enroll.tenant and x."program" = enroll.program
    and x."subject_type" = enroll.subject_type and x."subject_id" = enroll.subject_id
  for update;
  if v_row."status" = 'cancelled' then
    update "better_supabase"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "enrolled_by" = auth.uid(), "enrolled_at" = now(),
      "steps" = v_steps, "program_version" = v_program."version"
    where x."id" = v_row."id";
    update "better_supabase"."enrollments" x
  set "completed_steps" = (select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps") and y."completed_at" is not null),
    "status" = case when x."status" = 'cancelled' then 'cancelled' when ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps") and y."completed_at" is not null) >= cardinality(x."steps") and cardinality(x."steps") > 0) then 'completed' else 'active' end,
    "completed_at" = case when x."status" <> 'cancelled' and ((select count(*)::integer from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."id" and y."step" = any(x."steps") and y."completed_at" is not null) >= cardinality(x."steps") and cardinality(x."steps") > 0) then coalesce(x."completed_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_row."tenant_id" is not null then
    perform "better_supabase".emit_event('enrollment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'program', v_row."program", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'step', null::text, 'completedSteps', v_row."completed_steps", 'totalSteps', cardinality(v_row."steps")), 'enrollments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/enrollments');
  end if;
    v_id := v_row."id";
  else
    v_id := "better_supabase"."enrollment_ensure"(enroll.tenant, enroll.program, v_program."version", v_steps, enroll.subject_type, enroll.subject_id, auth.uid());
  end if;
  perform "better_supabase"."enrollment_schedule"(v_id);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_enrollment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return "better_supabase"."enrollment_json"(v_id);
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_sequence_enroll"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using enroll_in_sequence.sequence_id, enroll_in_sequence.subject_type, enroll_in_sequence.subject_id;
    end if;
  end;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_sequence."tenant_id" and x."program" = ('sequence:' || v_sequence."id"::text)
    and x."subject_type" = enroll_in_sequence.subject_type and x."subject_id" = enroll_in_sequence.subject_id
  for update;
  if v_row."id" is not null and v_row."status" = 'active' then
    return "better_supabase"."sequence_member_json"(v_row."id");
  end if;
  if v_row."id" is not null then
    -- Starting over: the run begins again with none of the steps done.
    perform "better_supabase"."enrollment_restart"(v_row."id", v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord), auth.uid());
    v_id := v_row."id";
  else
    v_id := "better_supabase"."enrollment_ensure"(v_sequence."tenant_id", ('sequence:' || v_sequence."id"::text), v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord),
      enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, auth.uid());
  end if;
  update "better_supabase"."enrollments" x
  set "sequence_id" = v_sequence."id", "sequence_address" = v_address, "sequence_name" = v_name, "sequence_mail_account_id" = v_account,
    "sequence_mail_thread_id" = null, "sequence_variables" = v_variables, "sequence_attempts" = 0, "sequence_last_error" = null, "updated_at" = now()
  where x."id" = v_id;
  perform "better_supabase"."sequence_place"(v_id);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_sequence_enroll"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return "better_supabase"."sequence_member_json"(v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_rule (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."automations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."automations" x where x."id" = remove_rule.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'automations.manage'), false)) then
    return false;
  end if;
  if v_row."default_key" is not null then
    raise exception 'A block ships this automation; turn it off instead of removing it' using errcode = '22023', hint = 'AUTOMATION_DEFAULT';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_automation_remove"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using remove_rule.id;
    end if;
  end;
  delete from "better_supabase"."automations" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('automation.deleted', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.deleted',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_automation_remove"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_workflow_start (
  key          text,
  workflow     text,
  payload      jsonb    DEFAULT '{}'::jsonb,
  tenant       uuid     DEFAULT NULL::uuid,
  actor        uuid     DEFAULT NULL::uuid,
  concurrency  integer  DEFAULT NULL::integer,
  debounce     interval DEFAULT NULL::interval,
  singleton    boolean  DEFAULT false,
  subject_type text     DEFAULT NULL::text,
  subject_id   text     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_workflow_start_request"(text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::uuid)', v_hook::oid::regproc)
        using request_workflow_start.key, request_workflow_start.workflow, request_workflow_start.tenant;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_admission'), pg_catalog.hashtext(key));
  if coalesce(singleton, false) and (
    "better_supabase"."workflow_admission_active"(key) > 0
    or exists (select 1 from "better_supabase"."workflow_start_requests" x where x."key" = key and x."status" = 'pending')
  ) then
    return jsonb_build_object('id', null, 'status', 'dropped');
  end if;
  if debounce is not null then
    update "better_supabase"."workflow_start_requests" x set "status" = 'superseded'
    where x."key" = key and x."status" = 'pending'
      and (x."claimed_until" is null or x."claimed_until" < now());
  end if;
  insert into "better_supabase"."workflow_start_requests" ("key", "workflow", "input", "tenant_id", "actor_id", "concurrency", "not_before", "subject_type", "subject_id")
  values (key, workflow, coalesce(payload -> 'input', '[]'::jsonb), tenant, actor, case when coalesce(singleton, false) then 1 else concurrency end, now() + coalesce(debounce, interval '0'), subject_type, subject_id)
  returning "id" into v_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_workflow_start_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'status', 'pending');
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
  v_old "better_supabase"."automations";
  v_row "better_supabase"."automations";
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
    raise exception 'rule must be an object' using errcode = '22023', hint = 'AUTOMATION_INVALID';
  end if;
  v_id := nullif(rule ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."automations" x where x."id" = v_id and x."organization_id" = save_rule.tenant for update;
    if v_old."id" is null then
      raise exception 'No rule in this organization has this id' using errcode = 'P0002', hint = 'AUTOMATION_NOT_FOUND';
    end if;
    if rule ? 'version' and (rule ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'The rule changed since it was read' using errcode = '40001', hint = 'AUTOMATION_CONFLICT';
    end if;
    if rule ? 'subjectType' and rule ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'A rule''s subject type can''t change' using errcode = '22023', hint = 'AUTOMATION_INVALID';
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when (v_enabled or coalesce(v_old."enabled", false)) then coalesce(better_supabase.can('tenant', save_rule.tenant, 'automations.publish'), false) else coalesce(better_supabase.can('tenant', save_rule.tenant, 'automations.write'), false) end)) then
    raise exception 'You need % to save this rule', case when (v_enabled or coalesce(v_old."enabled", false)) then '''automations.publish''' else '''automations.write''' end using errcode = '42501', hint = 'AUTOMATION_FORBIDDEN';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'A rule needs a subject type' using errcode = '22023', hint = 'AUTOMATION_INVALID';
  end if;
  if v_trigger is null or length(v_trigger) > 128 or v_trigger !~ '^[a-z][a-z0-9_]*([.:][a-z0-9_]+)*$' then
    raise exception 'A rule needs a trigger such as expense.submitted' using errcode = '22023', hint = 'AUTOMATION_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'A rule needs a name of at most 200 characters' using errcode = '22023', hint = 'AUTOMATION_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  if v_fields = '{}'::jsonb and v_old."default_key" is null then
    raise exception 'No rule fields for %; sync them first', v_subject_type using errcode = '22023', hint = 'RULE_SUBJECT_UNKNOWN';
  end if;
  perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  if jsonb_typeof(v_actions) is distinct from 'array' or jsonb_array_length(v_actions) > 20 then
    raise exception 'actions must be an array of at most 20 entries' using errcode = '22023', hint = 'AUTOMATION_ACTIONS_INVALID';
  end if;
  for v_action in select x.value from jsonb_array_elements(v_actions) x loop
    if jsonb_typeof(v_action) is distinct from 'object' or v_action ->> 'kind' is null
      or length(v_action ->> 'kind') > 128 or v_action ->> 'kind' !~ '^[a-z][a-z0-9_]*([.][a-z0-9_]+)*$'
      or (v_action ? 'config' and jsonb_typeof(v_action -> 'config') is distinct from 'object') then
      raise exception 'Every action needs a kind such as approvals.request and an optional config object' using errcode = '22023', hint = 'AUTOMATION_ACTIONS_INVALID';
    end if;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_automation_save"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using save_rule.tenant, save_rule.rule;
    end if;
  end;
  if v_old."id" is null then
    insert into "better_supabase"."automations" ("organization_id", "subject_type", "trigger", "name", "description", "conditions", "actions", "enabled", "stop_processing", "rank")
    values (save_rule.tenant, v_subject_type, v_trigger, v_name, v_description, v_conditions, v_actions, v_enabled, v_stop,
      case
    when (select max(x."rank" collate "C") from "better_supabase"."automations" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."automations" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."automations" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type)) then (select max(x."rank" collate "C") from "better_supabase"."automations" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."automations" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."automations" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."automations" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."automations" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
    returning * into v_row;
  elsif v_old."trigger" = v_trigger and v_old."name" = v_name
    and v_old."description" is not distinct from v_description
    and v_old."conditions" = v_conditions and v_old."actions" = v_actions
    and v_old."enabled" = v_enabled and v_old."stop_processing" = v_stop then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."organization_id", 'subjectType', v_old."subject_type", 'trigger', v_old."trigger", 'name', v_old."name", 'description', v_old."description", 'conditions', v_old."conditions", 'actions', v_old."actions", 'enabled', v_old."enabled", 'stopProcessing', v_old."stop_processing", 'rank', v_old."rank", 'version', v_old."version", 'createdBy', v_old."created_by", 'updatedBy', v_old."updated_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at", 'defaultKey', v_old."default_key");
  else
    update "better_supabase"."automations" x set
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
  insert into "better_supabase"."automation_versions" ("rule_id", "version", "organization_id", "name", "conditions", "actions", "saved_by")
  values (v_row."id", v_row."version", v_row."organization_id", v_row."name", v_row."conditions", v_row."actions", auth.uid())
  on conflict do nothing;
  if v_old."id" is null then
    perform "better_supabase".emit_event('automation.created', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.created',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  else
    perform "better_supabase".emit_event('automation.updated', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.updated',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  end if;
  if v_row."enabled" and not coalesce(v_old."enabled", false) then
    perform "better_supabase".emit_event('automation.enabled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.enabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  elsif not v_row."enabled" and coalesce(v_old."enabled", false) then
    perform "better_supabase".emit_event('automation.disabled', jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"), 'rules/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/automations');
  perform better_supabase.audit_event(
    event_type => 'automation.disabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_automation_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'defaultKey', v_row."default_key");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_sequence (
  tenant   uuid,
  sequence jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."sequences";
  v_row "better_supabase"."sequences";
  v_key text;
  v_name text;
  v_description text;
  v_status text;
  v_exit boolean;
  v_account uuid;
  v_steps jsonb;
  v_run uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_sequence.tenant is not null and coalesce(better_supabase.can('tenant', save_sequence.tenant, 'sequences.manage'), false))) then
    raise exception 'not allowed to manage sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if save_sequence.sequence is null or jsonb_typeof(save_sequence.sequence) <> 'object' then
    raise exception 'sequence must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  v_id := nullif(save_sequence.sequence ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."sequences" x
    where x."id" = v_id and x."tenant_id" = save_sequence.tenant
    for update;
    if v_old."id" is null then
      raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
    end if;
  end if;
  v_key := coalesce(save_sequence.sequence ->> 'key', v_old."key");
  v_name := trim(coalesce(save_sequence.sequence ->> 'name', v_old."name"));
  v_description := case when save_sequence.sequence ? 'description'
    then nullif(trim(save_sequence.sequence ->> 'description'), '') else v_old."description" end;
  v_status := coalesce(save_sequence.sequence ->> 'status', v_old."status"::text, 'draft');
  v_exit := case when save_sequence.sequence ? 'exitOnReply'
    then (save_sequence.sequence ->> 'exitOnReply')::boolean else coalesce(v_old."exit_on_reply", true) end;
  v_account := case when save_sequence.sequence ? 'accountId'
    then nullif(save_sequence.sequence ->> 'accountId', '')::uuid else v_old."mail_account_id" end;
  v_steps := case when save_sequence.sequence ? 'steps'
    then save_sequence.sequence -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits or "-", starting with a letter' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a sequence''s key can''t change' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_status not in ('draft', 'active', 'paused', 'archived') then
    raise exception 'status must be draft, active, paused or archived' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_exit is null then
    raise exception 'exitOnReply must be true or false' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  perform "better_supabase"."sequence_steps_check"(v_steps, true);
  if v_status = 'active' and jsonb_array_length(v_steps) = 0 then
    raise exception 'an active sequence needs at least one step' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_account is not null and not exists (
    select 1 from "better_supabase"."mail_accounts" k
    where k."id" = v_account and k."tenant_id" = save_sequence.tenant
      and k."status" <> 'disconnected'
  ) then
    raise exception 'accountId must be a connected mailbox of this organization' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_sequence_save"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using save_sequence.tenant, save_sequence.sequence;
    end if;
  end;
  if v_old."id" is null then
    insert into "better_supabase"."sequences" ("tenant_id", "key", "name", "description", "status", "exit_on_reply", "mail_account_id", "steps", "version", "created_by")
    values (save_sequence.tenant, v_key, v_name, v_description, v_status, v_exit, v_account, v_steps, 1, auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."sequences" x
    set "name" = v_name, "description" = v_description, "status" = v_status, "exit_on_reply" = v_exit,
      "mail_account_id" = v_account, "steps" = v_steps,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
    if v_old."steps" is distinct from v_row."steps" then
      perform "better_supabase"."sequence_resync"(v_row."id");
    end if;
    if v_row."status" = 'archived' and v_old."status" <> 'archived' then
      for v_run in
        select x."id" from "better_supabase"."enrollments" x
        where x."sequence_id" = v_row."id" and x."status" = 'active'
      loop
        perform "better_supabase"."sequence_exit"(v_run, 'archived');
      end loop;
    end if;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('sequence.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'sequences/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence.created',
    category => 'data',
    target_type => 'sequence',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created a sequence',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  else
    perform "better_supabase".emit_event('sequence.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'sequences/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence.updated',
    category => 'data',
    target_type => 'sequence',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated a sequence',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_sequence_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'status', v_row."status", 'exitOnReply', v_row."exit_on_reply", 'accountId', v_row."mail_account_id", 'steps', v_row."steps", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'active'), 'paused', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'cancelled'),
      'replied', count(*) filter (where m."status" = 'cancelled' and m."cancel_reason" = 'replied'))
    from "better_supabase"."enrollments" m where m."sequence_id" = v_row."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_inbox_message (
  conversation uuid,
  input        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_id uuid;
  v_author_type text;
  v_direction text;
  v_kind text := coalesce(input ->> 'kind', 'message');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = send_inbox_message.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_author_type := coalesce(input ->> 'author_type', 'bot');
    v_direction := case when v_author_type = 'contact' then 'inbound' else 'outbound' end;
  elsif exists (select 1 from "better_supabase"."people" p where p."id" = v_conv."contact_id" and p."user_id" = (select auth.uid())) then
    -- The conversation's own contact writes as the contact, staff included.
    if v_kind <> 'message' then
      raise exception 'contacts cannot write notes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
    end if;
    if input ? 'files' then
      raise exception 'contacts attach their own uploads' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
    end if;
    v_author_type := 'contact';
    v_direction := 'inbound';
  elsif coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false) then
    v_author_type := 'agent';
    v_direction := 'outbound';
  else
    raise exception 'not allowed to write in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inbox_message_send"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using send_inbox_message.conversation, send_inbox_message.input;
    end if;
  end;
  v_id := "better_supabase"."inbox_add_message"(v_conv."id", coalesce(input, '{}'::jsonb) - 'author_type', v_author_type, (select auth.uid()), v_direction);
  if v_author_type = 'agent' and v_kind = 'message' and v_conv."bot_mode" = 'bot' then
    update "better_supabase"."inbox_conversations" set "bot_mode" = 'human' where "id" = v_conv."id" returning * into v_conv;
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'handoff', (select auth.uid()), jsonb_build_object('from', 'bot', 'to', 'human', 'reason', 'agent_reply'));
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inbox_message_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return "better_supabase"."inbox_messages_json"(array[v_id]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_conversation_status (
  conversation  uuid,
  status        text,
  snoozed_until timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_before text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = set_conversation_status.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false)) then
    raise exception 'not allowed to change this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if status = 'snoozed' and (snoozed_until is null or snoozed_until <= now()) then
    raise exception 'snoozing needs a snoozed_until in the future' using errcode = '22023', hint = 'INBOX_SNOOZE_UNTIL';
  end if;
  v_before := v_conv."status";
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inbox_conversation_status_change"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_conv."id", set_conversation_status.status;
    end if;
  end;
  update "better_supabase"."inbox_conversations" set
    "status" = set_conversation_status.status,
    "snoozed_until" = case when set_conversation_status.status = 'snoozed' then set_conversation_status.snoozed_until end,
    "resolved_at" = case when set_conversation_status.status = 'resolved' then now() end
  where "id" = v_conv."id"
  returning * into v_conv;
  if status = 'snoozed' then
    perform "better_supabase"."enqueue_job"(queue => 'inbox_schedule', payload => jsonb_build_object('type', 'inbox.wake', 'conversation_id', v_conv."id"), delay => greatest(ceil(extract(epoch from (set_conversation_status.snoozed_until - now())))::integer, 0), dedupe_key => 'inbox-wake:' || v_conv."id"::text || ':' || extract(epoch from set_conversation_status.snoozed_until)::text, dedupe_running => false);
  end if;
  if v_before is distinct from status then
    insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'status', (select auth.uid()), jsonb_build_object('from', v_before, 'to', set_conversation_status.status));
    if status = 'resolved' then
      perform "better_supabase".emit_event('inbox_conversation.resolved', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    elsif v_before = 'resolved' then
      perform "better_supabase".emit_event('inbox_conversation.reopened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inbox_conversation_status_change"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_conv."id";
    end if;
  end;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_conversation (
  inbox uuid,
  input jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_contact uuid;
  v_contact_user uuid;
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_id uuid;
  v_staff boolean;
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inbox from "better_supabase"."inboxes" where "id" = start_conversation.inbox and "archived_at" is null;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  -- A signed-in caller who names no contact on a widget inbox is the
  -- visitor, staff included, so they can try their own widget.
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (select auth.uid()) is not null and not (input ? 'contact')
    and v_inbox."channel" = 'in_app' and coalesce((v_inbox."settings" ->> 'widget')::boolean, false) then
    v_staff := false;
    v_contact_input := jsonb_build_object(
      'user_id', (select auth.uid()),
      'name', v_contact_input ->> 'name',
      'email', coalesce((select auth.jwt()) ->> 'email', v_contact_input ->> 'email')
    );
  elsif coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_inbox."tenant_id", 'inbox.reply'), false) then
    v_staff := true;
    if jsonb_typeof(input -> 'contact') = 'string' then
      v_contact_input := jsonb_build_object('id', input ->> 'contact');
    end if;
    if v_contact_input = '{}'::jsonb then
      raise exception 'input.contact is required' using errcode = '22023', hint = 'CONTACT_REQUIRED';
    end if;
  else
    raise exception 'not allowed to open a conversation in this inbox' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inbox_conversation_start"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using start_conversation.inbox, start_conversation.input;
    end if;
  end;
  v_contact := "better_supabase"."resolve_person"(v_inbox."tenant_id", v_contact_input);
  select p."user_id" into v_contact_user from "better_supabase"."people" p where p."id" = v_contact;
  v_id := gen_random_uuid();
  insert into "better_supabase"."conversations" ("id", "tenant_id", "kind", "access", "created_by")
  values (v_id, v_inbox."tenant_id", 'inbox', 'tenant', (select auth.uid()));
  insert into "better_supabase"."inbox_conversations" ("id", "tenant_id", "inbox_id", "contact_id", "subject", "priority", "bot_mode", "thread_id", "assignee_id", "metadata")
  values (
    v_id, v_inbox."tenant_id", v_inbox."id", v_contact, input ->> 'subject', coalesce(input ->> 'priority', 'normal'),
    coalesce(input ->> 'bot_mode', v_inbox."bot_mode"), coalesce(input ->> 'thread_id', 'inbox:' || v_inbox."id"::text || ':' || v_id::text),
    case when v_staff then (input ->> 'assignee_id')::uuid end, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_conv;
  if v_contact_user is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_contact_user)
    on conflict do nothing;
  end if;
  if v_conv."assignee_id" is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_conv."assignee_id")
    on conflict do nothing;
  end if;
  insert into "better_supabase"."inbox_conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), '{}'::jsonb);
  perform "better_supabase".emit_event('inbox_conversation.opened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
  if input ? 'message' then
    perform "better_supabase"."inbox_add_message"(
      v_conv."id",
      case when jsonb_typeof(input -> 'message') = 'string' then jsonb_build_object('body', input ->> 'message') else input -> 'message' end,
      case when v_staff then (case when (select auth.uid()) is null then 'bot' else 'agent' end) else 'contact' end,
      (select auth.uid()),
      case when v_staff then 'outbound' else 'inbound' end
    );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inbox_conversation_start"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_conv."id";
    end if;
  end;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;
