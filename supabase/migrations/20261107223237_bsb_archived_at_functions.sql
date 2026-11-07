SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.add_subject_member (
  subject_type text,
  subject_id   text,
  user_id      uuid DEFAULT NULL::uuid,
  team_id      uuid DEFAULT NULL::uuid,
  role         text DEFAULT 'member'::text,
  starts_on    date DEFAULT NULL::date,
  ends_on      date DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_row "better_supabase"."subject_members";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (add_subject_member.subject_type = any (array['customer', 'drive_node']::text[])) then
    raise exception 'this subject type has no record team (subjects.<type>.team)' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  if (add_subject_member.user_id is null) = (add_subject_member.team_id is null) then
    raise exception 'pass exactly one of user_id and team_id' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  if add_subject_member.role is null or not (add_subject_member.role = any ('{lead,member}'::text[])) then
    raise exception 'role must be one of lead, member' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  if add_subject_member.ends_on < add_subject_member.starts_on then
    raise exception 'ends_on is before starts_on' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  begin
    case add_subject_member.subject_type
    when 'customer' then
      select s."organization_id" into v_tenant from "public"."customers" s
      where s."id" = (add_subject_member.subject_id)::uuid and s."archived_at" is null;
    when 'drive_node' then
      select s."tenant_id" into v_tenant from "better_supabase"."drive_nodes" s
      where s."id" = (add_subject_member.subject_id)::uuid and s."archived_at" is null;
      else
        v_tenant := null;
    end case;
  exception
    when invalid_text_representation then
      raise exception 'the subject id does not match its type''s id column' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end;
  if v_tenant is null then
    raise exception 'subject not found' using errcode = 'P0002', hint = 'SUBJECT_MEMBER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or coalesce(better_supabase.can('tenant', v_tenant, 'subjects.manage'), false)
      or (add_subject_member.subject_type = any (array[]::text[]) and coalesce("better_supabase"."can_subject"(add_subject_member.subject_type, add_subject_member.subject_id, 'manage'), false))) then
    raise exception 'not allowed to manage this record''s team' using errcode = '42501', hint = 'SUBJECT_MEMBER_FORBIDDEN';
  end if;
  if add_subject_member.user_id is not null and not exists (
    select 1 from "public"."memberships" om
    where om."organization_id" = v_tenant
      and om."user_id" = add_subject_member.user_id
  ) then
    raise exception 'user is not a member of the record''s tenant' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  if add_subject_member.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" tt
    where tt."id" = add_subject_member.team_id
      and tt."tenant_id" = v_tenant
  ) then
    raise exception 'team is not in the record''s tenant' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  if add_subject_member.user_id is not null then
    insert into "better_supabase"."subject_members" ("tenant_id", "subject_type", "subject_id", "user_id", "role", "starts_on", "ends_on", "created_by")
    values (v_tenant, add_subject_member.subject_type, add_subject_member.subject_id, add_subject_member.user_id, add_subject_member.role, add_subject_member.starts_on, add_subject_member.ends_on, auth.uid())
    on conflict ("subject_type", "subject_id", "user_id", "role") where "user_id" is not null
    do update set "starts_on" = excluded."starts_on", "ends_on" = excluded."ends_on"
    returning * into v_row;
  else
    insert into "better_supabase"."subject_members" ("tenant_id", "subject_type", "subject_id", "team_id", "role", "starts_on", "ends_on", "created_by")
    values (v_tenant, add_subject_member.subject_type, add_subject_member.subject_id, add_subject_member.team_id, add_subject_member.role, add_subject_member.starts_on, add_subject_member.ends_on, auth.uid())
    on conflict ("subject_type", "subject_id", "team_id", "role") where "team_id" is not null
    do update set "starts_on" = excluded."starts_on", "ends_on" = excluded."ends_on"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('subject_member.added', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role", 'endsOn', v_row."ends_on"), 'subjects/' || v_row."subject_type" || '/' || v_row."subject_id", (v_row."tenant_id")::text, null, 'better-supabase/subjects');
  perform better_supabase.audit_event(
    event_type => 'subject_member.added',
    category => 'access',
    target_type => 'subject_member',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role", 'endsOn', v_row."ends_on")
  );
  return jsonb_build_object(
      'id', v_row."id", 'organizationId', v_row."tenant_id",
      'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id",
      'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role",
      'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'endsAt', v_row."ends_at",
      'emergency', v_row."emergency", 'reason', v_row."reason",
      'active', (v_row."starts_on" is null or v_row."starts_on" <= current_date)
        and (v_row."ends_on" is null or v_row."ends_on" >= current_date)
        and (v_row."ends_at" is null or v_row."ends_at" > now()),
      'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$function$;

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
  where x."id" = assign_comment.message and x."sent_at" is not null and x."archived_at" is null;
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

CREATE OR REPLACE FUNCTION better_supabase.can_subject (
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  COST 1000
  SET search_path TO ''
  AS $function$
begin
  case can_subject.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end)
      );
    when 'conversation' then
      return exists (
        select 1 from "better_supabase"."conversations" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end)
      );
    when 'channel' then
      return exists (
        select 1 from "better_supabase"."channels" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'channels.manage'), false)
          else true
        end)
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.write'), false)
          else true
        end)
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.write'), false)
          else true
        end)
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.write'), false)
          else true
        end)
      );
    when 'course' then
      return exists (
        select 1 from "better_supabase"."courses" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.manage'), false)
          else true
        end)
      );
    when 'post' then
      return exists (
        select 1 from "better_supabase"."posts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.write'), false)
          else true
        end)
      );
    when 'activity' then
      return exists (
        select 1 from "better_supabase"."activities" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'activities.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'activities.write'), false)
          else true
        end)
      );
    when 'quote' then
      return exists (
        select 1 from "better_supabase"."quotes" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.write'), false)
          else true
        end)
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tasks.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tasks.write'), false)
          else true
        end)
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.write'), false)
          else true
        end)
      );
    when 'invoice' then
      return exists (
        select 1 from "better_supabase"."invoices" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.write'), false)
          else true
        end)
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.manage'), false)
          else true
        end)
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'rfq' then
      return exists (
        select 1 from "better_supabase"."rfqs" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'rfqs.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'rfqs.write'), false)
          else true
        end)
      );
    when 'till' then
      return exists (
        select 1 from "better_supabase"."tills" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tills.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tills.write'), false)
          else true
        end)
      );
    when 'order' then
      return exists (
        select 1 from "better_supabase"."orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.manage'), false)
          else true
        end)
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.write'), false)
          else true
        end)
      );
    when 'booking' then
      return exists (
        select 1 from "better_supabase"."bookings" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.manage'), false)
          else true
        end)
      );
    when 'asset' then
      return exists (
        select 1 from "better_supabase"."assets" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end)
      );
    when 'asset_location' then
      return exists (
        select 1 from "better_supabase"."asset_locations" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end)
      );
    when 'lease' then
      return exists (
        select 1 from "better_supabase"."leases" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.manage'), false)
          else true
        end)
      );
    when 'expense_report' then
      return exists (
        select 1 from "better_supabase"."expense_reports" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          else true
        end)
      );
    when 'expense_line' then
      return exists (
        select 1 from "better_supabase"."expense_lines" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.submit'), false)
          else true
        end)
      );
    when 'donation_fund' then
      return exists (
        select 1 from "better_supabase"."donation_funds" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.manage'), false)
          else true
        end)
      );
    when 'work_order' then
      return exists (
        select 1 from "better_supabase"."work_orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.manage'), false)
          else true
        end)
      );
    when 'shipment' then
      return exists (
        select 1 from "better_supabase"."shipments" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.manage'), false)
          else true
        end)
      );
    when 'contract' then
      return exists (
        select 1 from "better_supabase"."contracts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.write'), false)
          else true
        end)
      );
    when 'control' then
      return exists (
        select 1 from "better_supabase"."controls" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.manage'), false)
          else true
        end)
      );
    when 'compliance_policy' then
      return exists (
        select 1 from "better_supabase"."compliance_policies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.manage'), false)
          else true
        end)
      );
    when 'qualification_type' then
      return exists (
        select 1 from "better_supabase"."qualification_types" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'qualifications.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'qualifications.manage'), false)
          else true
        end)
      );
    when 'risk' then
      return exists (
        select 1 from "better_supabase"."risks" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'risks.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'risks.write'), false)
          else true
        end)
      );
    when 'case' then
      return exists (
        select 1 from "better_supabase"."cases" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'cases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'cases.write'), false)
          else true
        end)
      );
    when 'inspection' then
      return exists (
        select 1 from "better_supabase"."inspections" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.write'), false)
          else true
        end)
      );
    when 'inspection_program' then
      return exists (
        select 1 from "better_supabase"."inspection_programs" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.manage'), false)
          else true
        end)
      );
    when 'inspection_finding' then
      return exists (
        select 1 from "better_supabase"."inspection_findings" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.write'), false)
          else true
        end)
      );
    when 'form' then
      return exists (
        select 1 from "better_supabase"."forms" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.manage'), false)
          else true
        end)
      );
    when 'meeting' then
      return exists (
        select 1 from "better_supabase"."meetings" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.write'), false)
          else true
        end)
      );
    when 'meeting_decision' then
      return exists (
        select 1 from "better_supabase"."meeting_decisions" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.write'), false)
          else true
        end)
      );
    when 'maintenance_plan' then
      return exists (
        select 1 from "better_supabase"."maintenance_plans" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'maintenance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'maintenance.manage'), false)
          else true
        end)
      );
    when 'dam_usage_right' then
      return exists (
        select 1 from "better_supabase"."dam_usage_rights" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dam.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dam.write'), false)
          else true
        end)
      );
    when 'lims_sample' then
      return exists (
        select 1 from "better_supabase"."lims_samples" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'lims.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'lims.write'), false)
          else true
        end)
      );
    when 'tax_code' then
      return exists (
        select 1 from "better_supabase"."tax_codes" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tax.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tax.manage'), false)
          else true
        end)
      );
    when 'production_order' then
      return exists (
        select 1 from "better_supabase"."production_orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.write'), false)
          else true
        end)
      );
    when 'work_center' then
      return exists (
        select 1 from "better_supabase"."work_centers" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.manage'), false)
          else true
        end)
      );
    when 'bank_account' then
      return exists (
        select 1 from "better_supabase"."bank_accounts" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'banking.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'banking.manage'), false)
          else true
        end)
      );
    when 'care_plan' then
      return exists (
        select 1 from "better_supabase"."care_plans" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'care_plans.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'care_plans.write'), false)
          else true
        end)
      );
    when 'incident' then
      return exists (
        select 1 from "better_supabase"."incidents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.write'), false)
          else true
        end)
      );
    when 'content_entry' then
      return exists (
        select 1 from "better_supabase"."content_entries" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.write'), false)
          else true
        end)
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.write'), false)
          else true
        end)
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then (coalesce(better_supabase.can('tenant', s."organization_id", 'customers.read'), false) or "better_supabase"."is_subject_member"('customer', s."id"::text))
          when 'write' then (coalesce(better_supabase.can('tenant', s."organization_id", 'customers.write'), false) or "better_supabase"."is_subject_member"('customer', s."id"::text))
          else true
        end)
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then ((coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', s."id"::text))
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.manage'), false)
          when 'comment' then coalesce("better_supabase"."drive_can_comment"(s."id"), false)
          when 'fields' then coalesce("better_supabase"."drive_node_writable"(s."id"), false)
          else true
        end)
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.write'), false)
          else true
        end)
      );
    when 'change_request' then
      return exists (
        select 1 from "public"."change_requests" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and true
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    else
      return false;
  end case;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject_for (
  member       uuid,
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  case can_subject_for.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          else false
        end
      );
    when 'conversation' then
      return exists (
        select 1 from "better_supabase"."conversations" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          else false
        end
      );
    when 'channel' then
      return exists (
        select 1 from "better_supabase"."channels" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'channels.manage'), false)
          else false
        end
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contacts.write'), false)
          else false
        end
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contacts.write'), false)
          else false
        end
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.write'), false)
          else false
        end
      );
    when 'course' then
      return exists (
        select 1 from "better_supabase"."courses" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'courses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'courses.manage'), false)
          else false
        end
      );
    when 'post' then
      return exists (
        select 1 from "better_supabase"."posts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'posts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'posts.write'), false)
          else false
        end
      );
    when 'activity' then
      return exists (
        select 1 from "better_supabase"."activities" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'activities.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'activities.write'), false)
          else false
        end
      );
    when 'quote' then
      return exists (
        select 1 from "better_supabase"."quotes" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'quotes.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'quotes.write'), false)
          else false
        end
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tasks.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tasks.write'), false)
          else false
        end
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.write'), false)
          else false
        end
      );
    when 'invoice' then
      return exists (
        select 1 from "better_supabase"."invoices" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'invoices.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'invoices.write'), false)
          else false
        end
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.manage'), false)
          else false
        end
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'rfq' then
      return exists (
        select 1 from "better_supabase"."rfqs" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'rfqs.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'rfqs.write'), false)
          else false
        end
      );
    when 'till' then
      return exists (
        select 1 from "better_supabase"."tills" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tills.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tills.write'), false)
          else false
        end
      );
    when 'order' then
      return exists (
        select 1 from "better_supabase"."orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'orders.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'orders.manage'), false)
          else false
        end
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.write'), false)
          else false
        end
      );
    when 'booking' then
      return exists (
        select 1 from "better_supabase"."bookings" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'bookings.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'bookings.manage'), false)
          else false
        end
      );
    when 'asset' then
      return exists (
        select 1 from "better_supabase"."assets" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.manage'), false)
          else false
        end
      );
    when 'asset_location' then
      return exists (
        select 1 from "better_supabase"."asset_locations" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.manage'), false)
          else false
        end
      );
    when 'lease' then
      return exists (
        select 1 from "better_supabase"."leases" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.manage'), false)
          else false
        end
      );
    when 'expense_report' then
      return exists (
        select 1 from "better_supabase"."expense_reports" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.manage'), false)
          else false
        end
      );
    when 'expense_line' then
      return exists (
        select 1 from "better_supabase"."expense_lines" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.submit'), false)
          else false
        end
      );
    when 'donation_fund' then
      return exists (
        select 1 from "better_supabase"."donation_funds" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'donations.manage'), false)
          else false
        end
      );
    when 'work_order' then
      return exists (
        select 1 from "better_supabase"."work_orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dispatch.manage'), false)
          else false
        end
      );
    when 'shipment' then
      return exists (
        select 1 from "better_supabase"."shipments" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'shipments.manage'), false)
          else false
        end
      );
    when 'contract' then
      return exists (
        select 1 from "better_supabase"."contracts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contracts.write'), false)
          else false
        end
      );
    when 'control' then
      return exists (
        select 1 from "better_supabase"."controls" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'compliance.manage'), false)
          else false
        end
      );
    when 'compliance_policy' then
      return exists (
        select 1 from "better_supabase"."compliance_policies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'compliance.manage'), false)
          else false
        end
      );
    when 'qualification_type' then
      return exists (
        select 1 from "better_supabase"."qualification_types" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'qualifications.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'qualifications.manage'), false)
          else false
        end
      );
    when 'risk' then
      return exists (
        select 1 from "better_supabase"."risks" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'risks.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'risks.write'), false)
          else false
        end
      );
    when 'case' then
      return exists (
        select 1 from "better_supabase"."cases" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'cases.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'cases.write'), false)
          else false
        end
      );
    when 'inspection' then
      return exists (
        select 1 from "better_supabase"."inspections" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.write'), false)
          else false
        end
      );
    when 'inspection_program' then
      return exists (
        select 1 from "better_supabase"."inspection_programs" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.manage'), false)
          else false
        end
      );
    when 'inspection_finding' then
      return exists (
        select 1 from "better_supabase"."inspection_findings" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.write'), false)
          else false
        end
      );
    when 'form' then
      return exists (
        select 1 from "better_supabase"."forms" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'forms.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'forms.manage'), false)
          else false
        end
      );
    when 'meeting' then
      return exists (
        select 1 from "better_supabase"."meetings" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'meetings.write'), false)
          else false
        end
      );
    when 'meeting_decision' then
      return exists (
        select 1 from "better_supabase"."meeting_decisions" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'meetings.write'), false)
          else false
        end
      );
    when 'maintenance_plan' then
      return exists (
        select 1 from "better_supabase"."maintenance_plans" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'maintenance.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'maintenance.manage'), false)
          else false
        end
      );
    when 'dam_usage_right' then
      return exists (
        select 1 from "better_supabase"."dam_usage_rights" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dam.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dam.write'), false)
          else false
        end
      );
    when 'lims_sample' then
      return exists (
        select 1 from "better_supabase"."lims_samples" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'lims.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'lims.write'), false)
          else false
        end
      );
    when 'tax_code' then
      return exists (
        select 1 from "better_supabase"."tax_codes" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tax.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tax.manage'), false)
          else false
        end
      );
    when 'production_order' then
      return exists (
        select 1 from "better_supabase"."production_orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'manufacturing.write'), false)
          else false
        end
      );
    when 'work_center' then
      return exists (
        select 1 from "better_supabase"."work_centers" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'manufacturing.manage'), false)
          else false
        end
      );
    when 'bank_account' then
      return exists (
        select 1 from "better_supabase"."bank_accounts" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'banking.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'banking.manage'), false)
          else false
        end
      );
    when 'care_plan' then
      return exists (
        select 1 from "better_supabase"."care_plans" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'care_plans.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'care_plans.write'), false)
          else false
        end
      );
    when 'incident' then
      return exists (
        select 1 from "better_supabase"."incidents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'incidents.write'), false)
          else false
        end
      );
    when 'content_entry' then
      return exists (
        select 1 from "better_supabase"."content_entries" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'content.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'content.write'), false)
          else false
        end
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.write'), false)
          else false
        end
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then (coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.read'), false) or exists (
            select 1 from "better_supabase"."subject_members" m
            where m."subject_type" = 'customer'
              and m."subject_id" = s."id"::text
              and m."tenant_id" = s."organization_id"
              and (m."user_id" = can_subject_for.member or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = can_subject_for.member)))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())))
          when 'write' then (coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.write'), false) or exists (
            select 1 from "better_supabase"."subject_members" m
            where m."subject_type" = 'customer'
              and m."subject_id" = s."id"::text
              and m."tenant_id" = s."organization_id"
              and (m."user_id" = can_subject_for.member or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = can_subject_for.member)))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())))
          else false
        end
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then (false or exists (
            select 1 from "better_supabase"."subject_members" m
            where m."subject_type" = 'drive_node'
              and m."subject_id" = s."id"::text
              and m."tenant_id" = s."tenant_id"
              and (m."user_id" = can_subject_for.member or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = can_subject_for.member)))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())))
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.manage'), false)
          when 'comment' then false
          when 'fields' then false
          else false
        end
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.write'), false)
          else false
        end
      );
    when 'change_request' then
      return exists (
        select 1 from "public"."change_requests" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and false
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_counts (
  tenant       uuid,
  subject_type text,
  subject_ids  text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return (
    select coalesce(jsonb_object_agg(s.subject_id, s.n), '{}'::jsonb)
    from (
      select c."subject_id" as subject_id, count(*) as n
      from "better_supabase"."conversations" c
      join "better_supabase"."messages" x on x."conversation_id" = c."id"
      where c."tenant_id" = comment_counts.tenant and c."kind" = 'subject'
        and c."subject_type" = comment_counts.subject_type
        and c."subject_id" = any (comment_counts.subject_ids)
        and x."sent_at" is not null and x."archived_at" is null
      group by 1
    ) s
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_sent (
  message uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg record;
  v_conv record;
  v_user uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" x
  where x."id" = comment_sent.message and x."author_id" = auth.uid()
    and x."sent_at" is not null and x."archived_at" is null;
  if not found then
    return;
  end if;
  select * into v_conv from "better_supabase"."conversations" c
  where c."id" = v_msg."conversation_id" and c."kind" = 'subject';
  if not found then
    return;
  end if;
  foreach v_user in array array(select distinct x from unnest(array[v_msg."author_id"] || v_msg."mentions") x where x = v_msg."author_id" or coalesce(better_supabase.can_user(x, 'tenant', v_msg."tenant_id", 'messages.read'), false)) loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_conv."tenant_id", v_user, v_conv."subject_type", v_conv."subject_id", 'participating')
    on conflict do nothing;
  end loop;
  if (exists (
      select 1 from "better_supabase"."notification_subscriptions" s
      where s."subject_type" = v_conv."subject_type" and s."subject_id" = v_conv."subject_id" and s."organization_id" = v_conv."tenant_id"
        and s."level" in ('all', 'participating')
        and not s."user_id" = any (array[v_msg."author_id"] || v_msg."mentions")
    ) or to_regprocedure('"public"."notification_audience"(jsonb)') is not null) then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'comment.posted',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', v_conv."subject_type",
      'subject_id', v_conv."subject_id",
      'subject_label', "better_supabase"."subject_title"(v_conv."subject_type", v_conv."subject_id"),
      'summary', left(v_msg."body", 140),
      'recipients', '[]'::jsonb,
      'exclude', to_jsonb(v_msg."mentions"),
      'key', 'comment.posted:' || v_msg."id"::text,
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.copy_comments (
  tenant    uuid,
  from_type text,
  from_id   text,
  to_type   text,
  to_id     text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_from uuid;
  v_to uuid;
  v_copied integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role copies comments' using errcode = '42501', hint = 'COMMENT_FORBIDDEN';
  end if;
  select c."id" into v_from from "better_supabase"."conversations" c
  where c."tenant_id" = copy_comments.tenant and c."kind" = 'subject'
    and c."subject_type" = copy_comments.from_type and c."subject_id" = copy_comments.from_id;
  if v_from is null then
    return 0;
  end if;
  insert into "better_supabase"."conversations" ("tenant_id", "kind", "access", "subject_type", "subject_id")
  values (copy_comments.tenant, 'subject', 'subject', copy_comments.to_type, copy_comments.to_id)
  on conflict do nothing;
  select c."id" into v_to from "better_supabase"."conversations" c
  where c."tenant_id" = copy_comments.tenant and c."kind" = 'subject'
    and c."subject_type" = copy_comments.to_type and c."subject_id" = copy_comments.to_id;
  with copies as materialized (
    select y."id" as old_id, gen_random_uuid() as new_id
    from "better_supabase"."messages" y
    where y."conversation_id" = v_from and y."sent_at" is not null
  ), inserted as (
    insert into "better_supabase"."messages" ("id", "tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "anchor", "mentions", "reply_count", "last_reply_at", "reply_user_ids", "sent_at", "edited_at", "archived_at", "created_at")
    select n.new_id, y."tenant_id", v_to, p.new_id, r.new_id, y."author_id",
      y."body", y."document", y."anchor", y."mentions", y."reply_count", y."last_reply_at", y."reply_user_ids", y."sent_at", y."edited_at", y."archived_at", y."created_at"
    from "better_supabase"."messages" y
    join copies n on n.old_id = y."id"
    left join copies p on p.old_id = y."parent_id"
    left join copies r on r.old_id = y."thread_id"
    order by y."sent_at", y."id"
    returning 1
  )
  select count(*)::integer into v_copied from inserted;
  return v_copied;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_message (
  message uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = delete_message.message and m."archived_at" is null
    and "better_supabase"."can_conversation"(m."conversation_id", 'read');
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_msg."author_id" = auth.uid(), false) or "better_supabase"."can_conversation"(v_msg."conversation_id", 'moderate')) then
    raise exception 'not allowed to delete this message' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  update "better_supabase"."messages" m set "body" = '', "document" = null, "mentions" = '{}', "mention_scope" = null,
    "pinned_at" = null, "pinned_by" = null, "archived_at" = now()
  where m."id" = v_msg."id"
  returning * into v_msg;
  delete from "better_supabase"."message_edits" x where x."message_id" = v_msg."id";
  delete from "better_supabase"."message_record_mentions" x where x."message_id" = v_msg."id";
  delete from "better_supabase"."attachments" a
  where a."subject_type" = 'message' and a."subject_id" = v_msg."id"::text;
  if v_msg."sent_at" is not null then
    perform "better_supabase".emit_event('message.deleted', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text)
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_approvals (
  node uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_approvals.node and x."archived_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(r.value || jsonb_build_object(
      'attachmentId', r.value -> 'payload' ->> 'attachmentId',
      'revision', (r.value -> 'payload' ->> 'revision')::integer,
      'current', r.value -> 'payload' ->> 'attachmentId' = v_node."attachment_id"::text
    ) order by r.ordinality), '[]'::jsonb)
    from jsonb_array_elements("better_supabase"."list_approvals"(v_node."tenant_id", null, false, 'drive_node', v_node."id"::text, 200, null)) with ordinality r
    where r.value ->> 'action' = 'approve'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_can_upload (
  folder uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce((
    select x."kind" = 'folder' and not (coalesce(x."source"::text, 'internal') not in ('internal', 'request') or false) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'editor') or (auth.uid() is not null
      and coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false)
      and exists (select 1 from "better_supabase"."drive_grants" ug
        where ug."node_id" = any ("better_supabase"."drive_ancestors"(x."id")) and ug."role" = 'contributor' and (ug."expires_at" is null or ug."expires_at" > now())
          and ((ug."principal_type" = 'user' and ug."principal_id" = auth.uid()::text)
      or (ug."principal_type" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = ug."principal_id"::text and tm."user_id" = auth.uid()))
      or (ug."principal_type" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = x."tenant_id" and mr."user_id" = auth.uid() and mr."role"::text = ug."principal_id"))))))
    from "better_supabase"."drive_nodes" x where x."id" = drive_can_upload.folder and x."archived_at" is null
  ), false)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_changes (
  tenant    uuid,
  after     text    DEFAULT NULL::text,
  page_size integer DEFAULT 200,
  drive     uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_at timestamptz;
  v_id uuid;
  v_size integer := least(greatest(coalesce(drive_changes.page_size, 200), 1), 500);
  v_row "better_supabase"."drive_nodes"%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_more boolean := false;
  v_cursor text := drive_changes.after;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_changes.tenant, 'drive.read'), false)) then
    raise exception 'not allowed to read this organization''s drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_changes.after is not null then
    begin
      v_at := split_part(drive_changes.after, '|', 1)::timestamptz;
      v_id := split_part(drive_changes.after, '|', 2)::uuid;
    exception when others then
      raise exception 'the changes cursor is not valid' using errcode = '22023', hint = 'DRIVE_CURSOR_INVALID';
    end;
  end if;
  for v_row in
    select * from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_changes.tenant
      and (v_at is null or (x."updated_at", x."id") > (v_at, v_id))
      and x."updated_at" <= now() - interval '5 seconds'
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
    order by x."updated_at", x."id"
    limit v_size + 1
  loop
    v_count := v_count + 1;
    if v_count > v_size then
      v_more := true;
      exit;
    end if;
    v_items := v_items || jsonb_build_array(case when v_row."archived_at" is not null
        then jsonb_build_object('removed', true, 'id', v_row."id")
        else jsonb_build_object('removed', false, 'node', ("better_supabase"."drive_node_json"(v_row) || jsonb_build_object('role', "better_supabase"."drive_role"((v_row)."id"), 'readOnly', (coalesce((v_row)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_row)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_row)."id")))) end);
    v_cursor := to_char(v_row."updated_at" at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || v_row."id"::text;
  end loop;
  return jsonb_build_object('changes', v_items, 'cursor', v_cursor, 'more', v_more);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_check_parent (
  tenant uuid,
  parent uuid,
  drive  uuid
)
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_parent "better_supabase"."drive_nodes"%rowtype;
begin
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return;
  end if;
  if drive_check_parent.parent is null then
    if not coalesce(better_supabase.can('tenant', drive_check_parent.tenant, 'drive.create'), false) then
      raise exception 'not allowed to create items in this drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
    end if;
    return;
  end if;
  select * into v_parent from "better_supabase"."drive_nodes" x
  where x."id" = drive_check_parent.parent and x."tenant_id" = drive_check_parent.tenant and x."archived_at" is null;
  if not found or not "better_supabase"."drive_can"(v_parent."id", 'viewer') then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not "better_supabase"."drive_can"(v_parent."id", 'editor') then
    raise exception 'not allowed to add items to this folder' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if v_parent."kind" <> 'folder' then
    raise exception 'a file can''t hold other items' using errcode = '22023', hint = 'DRIVE_PARENT_NOT_FOLDER';
  end if;
  if (coalesce(v_parent."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_commit (
  node       uuid,
  attachment uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_commit.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer') or "better_supabase"."drive_uploaded_own"(v_node."id")) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor') or "better_supabase"."drive_uploaded_own"(v_node."id")) then
    raise exception 'not allowed to change this file' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if not exists (
    select 1 from "better_supabase"."attachments" f where f."id" = drive_commit.attachment
      and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
  ) then
    raise exception 'this upload does not belong to the file' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  perform "better_supabase"."confirm_attachment"(drive_commit.attachment);
  select * into v_file from "better_supabase"."attachments" f where f."id" = drive_commit.attachment;
  if v_node."attachment_id" is distinct from v_file."id" then
    update "better_supabase"."drive_nodes" x set "attachment_id" = v_file."id", "preview_pages" = null, "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
    perform "better_supabase"."version_insert"(v_node."tenant_id", 'drive_node', v_node."id"::text,
      jsonb_build_object('attachmentId', v_file."id", 'name', v_file."name", 'mimeType', v_file."mime_type", 'size', v_file."size"),
      v_file."bucket" || '/' || v_file."object_path", null, 'manual', false, auth.uid());
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    return jsonb_build_object('id', v_node."id", 'attachmentId', v_file."id", 'committed', true);
  end if;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_create_file (
  tenant    uuid,
  parent    uuid,
  name      text,
  mime_type text,
  size      bigint,
  conflict  text   DEFAULT NULL::text,
  fields    jsonb  DEFAULT NULL::jsonb,
  drive     uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_name text := "better_supabase"."drive_clean_name"(drive_create_file.name);
  v_conflict text := "better_supabase"."drive_conflict"(drive_create_file.conflict);
  v_drive uuid := drive_create_file.drive;
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_attachment jsonb;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and drive_create_file.parent is not null
    and exists (select 1 from "better_supabase"."drive_nodes" x where x."id" = drive_create_file.parent and x."tenant_id" = drive_create_file.tenant and x."archived_at" is null)
    and not "better_supabase"."drive_can"(drive_create_file.parent, 'viewer') and "better_supabase"."drive_can_upload"(drive_create_file.parent) then
    v_node := "better_supabase"."drive_insert_node"(drive_create_file.tenant, null, drive_create_file.parent, 'file', v_name, 'rename', drive_create_file.fields);
    v_attachment := "better_supabase"."create_attachment"(v_node."tenant_id", v_node."name", drive_create_file.mime_type, drive_create_file.size, 'drive_node', v_node."id"::text);
    return jsonb_build_object('id', v_node."id", 'attachment', v_attachment);
  end if;
  perform "better_supabase"."drive_check_parent"(drive_create_file.tenant, drive_create_file.parent, drive_create_file.drive);
  if v_conflict = 'replace' then
    perform "better_supabase"."drive_lock_siblings"(drive_create_file.tenant, v_drive, drive_create_file.parent);
    select * into v_node from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_create_file.tenant and x."parent_id" is not distinct from drive_create_file.parent and x."archived_at" is null and lower(x."name") = lower(v_name);
    if found then
      if v_node."kind" <> 'file' then
        raise exception 'a folder already has this name' using errcode = '23505', hint = 'DRIVE_NAME_CONFLICT';
      end if;
      return "better_supabase"."drive_upload_revision"(v_node."id", drive_create_file.mime_type, drive_create_file.size);
    end if;
  end if;
  v_node := "better_supabase"."drive_insert_node"(drive_create_file.tenant, v_drive, drive_create_file.parent, 'file', v_name, v_conflict, drive_create_file.fields);
  return jsonb_build_object('node', "better_supabase"."drive_node_json"(v_node), 'attachment',
    "better_supabase"."create_attachment"(v_node."tenant_id", v_node."name", drive_create_file.mime_type, drive_create_file.size, 'drive_node', v_node."id"::text));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_obsolete (
  node   uuid,
  reason text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_obsolete.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be obsoleted' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to withdraw this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if v_node."document_status" is distinct from 'effective' then
    raise exception 'only an effective document can be made obsolete' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'obsolete', drive_document_obsolete.reason);
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive_node.obsoleted', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'reason', drive_document_obsolete.reason), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.obsoleted',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document made obsolete',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'reason', drive_document_obsolete.reason)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_release (
  node       uuid,
  attachment uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
  v_version uuid;
  v_inserted jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or exists (
    select 1 from "better_supabase"."approval_requests" q
    where q."id"::text = nullif(current_setting('better_supabase.approval', true), '')
      and q."status" = 'approved' and q."action" = 'release'
      and q."subject_type" = 'drive_node' and q."subject_id" = drive_document_release.node::text
  )) then
    raise exception 'only an approved release request releases a document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_release.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be released' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if v_node."document_status" is null or v_node."document_status" not in ('in_review', 'effective') then
    raise exception 'only a document in review or an effective one can be released' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  select * into v_file from "better_supabase"."attachments" f
  where f."id" = drive_document_release.attachment
    and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
    and f."uploaded_at" is not null;
  if not found then
    raise exception 'that version of the file was not found' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  select r."id" into v_version from "better_supabase"."versions" r
  where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
    and r."content" ->> 'attachmentId' = v_file."id"::text
  order by r."number" desc limit 1;
  if v_version is null then
    v_inserted := "better_supabase"."version_insert"(v_node."tenant_id", 'drive_node', v_node."id"::text,
      jsonb_build_object('attachmentId', v_file."id", 'name', v_file."name", 'mimeType', v_file."mime_type", 'size', v_file."size"),
      v_file."bucket" || '/' || v_file."object_path", 'effective', 'manual', true, auth.uid());
    v_version := (v_inserted ->> 'id')::uuid;
  else
    update "better_supabase"."versions" r set "label" = 'effective', "frozen" = true where r."id" = v_version;
  end if;
  update "better_supabase"."versions" r set "label" = 'superseded'
  where r."id" = v_node."effective_version_id" and r."id" <> v_version;
  update "better_supabase"."drive_nodes" x set "effective_version_id" = v_version, "effective_at" = now(),
    "next_review_on" = (current_date + make_interval(months => coalesce(v_node."review_interval_months", 12)))::date, "review_notified_for" = null
  where x."id" = v_node."id";
  if v_node."document_status" = 'in_review' then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'effective', 'released');
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive_node.released', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'versionId', v_version, 'attachmentId', v_file."id"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.released',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document released',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'versionId', v_version, 'attachmentId', v_file."id")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_review (
  node    uuid,
  outcome text,
  note    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_review.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be reviewed' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_node."document_owner_id" = auth.uid() or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to review this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_document_review.outcome is null or drive_document_review.outcome not in ('unchanged', 'revise') then
    raise exception 'outcome must be unchanged or revise' using errcode = '22023', hint = 'DRIVE_DOCUMENT_REVIEW_INVALID';
  end if;
  if v_node."document_status" is distinct from 'effective' then
    raise exception 'only an effective document is reviewed' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if drive_document_review.outcome = 'unchanged' then
    update "better_supabase"."drive_nodes" x set "next_review_on" = (current_date + make_interval(months => coalesce(v_node."review_interval_months", 12)))::date, "review_notified_for" = null
    where x."id" = v_node."id"
    returning * into v_node;
  end if;
  perform "better_supabase".emit_event('drive_node.reviewed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'outcome', drive_document_review.outcome, 'note', drive_document_review.note, 'nextReviewOn', v_node."next_review_on"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.reviewed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document reviewed',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'outcome', drive_document_review.outcome, 'note', drive_document_review.note, 'nextReviewOn', v_node."next_review_on")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_save (
  node                   uuid,
  document_type          text,
  owner_id               uuid    DEFAULT NULL::uuid,
  review_interval_months integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_seq bigint;
  v_number text;
  v_entity text;
  v_format text;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_save.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be a controlled document' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to control this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if drive_document_save.document_type is null or not (drive_document_save.document_type = any (array['sop', 'policy', 'form']::text[])) then
    raise exception 'that document type is not in options.control.types' using errcode = '22023', hint = 'DRIVE_DOCUMENT_TYPE_UNKNOWN';
  end if;
  if v_node."document_status" = 'obsolete' then
    raise exception 'an obsolete document can''t change' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if drive_document_save.owner_id is not null and not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = v_node."tenant_id" and mu."user_id" = drive_document_save.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'DRIVE_DOCUMENT_OWNER_INVALID';
  end if;
  v_number := v_node."document_number";
  if v_number is null then
    case drive_document_save.document_type
      when 'sop' then
        v_entity := 'drive_document_sop';
        v_format := 'SOP-{n:4}';
      else
        v_entity := 'drive_document';
        v_format := 'DOC-{n:5}';
    end case;
    if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = v_entity then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = v_entity then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_node."tenant_id", v_entity, v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_node."tenant_id", v_entity, now());
    v_number := better_supabase.format_assigned_number(v_format, v_seq, now());
  end if;
  end if;
  update "better_supabase"."drive_nodes" x set "document_number" = v_number,
    "document_type" = drive_document_save.document_type,
    "document_owner_id" = coalesce(drive_document_save.owner_id, x."document_owner_id", auth.uid()),
    "review_interval_months" = coalesce(drive_document_save.review_interval_months, x."review_interval_months"), "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  if v_node."document_status" is null then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'draft', null);
    select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  end if;
  perform "better_supabase".emit_event('drive_node.document_saved', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.document_saved',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document saved',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_submit (
  node       uuid,
  attachment uuid DEFAULT NULL::uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
  v_revision integer;
  v_request jsonb;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_submit.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be released' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to submit this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if v_node."document_status" is null then
    raise exception 'save the file as a controlled document first' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if not (v_node."document_status" = 'draft' or (v_node."document_status" in ('in_review', 'effective') and not exists (
    select 1 from "better_supabase"."approval_requests" q
    where q."subject_type" = 'drive_node' and q."subject_id" = v_node."id"::text
      and q."action" = 'release' and q."status" = 'pending'
  ))) then
    raise exception 'only a draft, or an effective document without a pending release, can be submitted' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  select * into v_file from "better_supabase"."attachments" f
  where f."id" = coalesce(drive_document_submit.attachment, v_node."attachment_id")
    and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
    and f."uploaded_at" is not null;
  if not found then
    raise exception 'that version of the file was not found' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  select r."number" into v_revision from "better_supabase"."versions" r
  where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
    and r."content" ->> 'attachmentId' = v_file."id"::text
  order by r."number" limit 1;
  if v_node."document_status" = 'draft' then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'in_review', drive_document_submit.reason);
  end if;
  v_request := "better_supabase"."request_approval"(v_node."tenant_id", 'drive_node', v_node."id"::text, 'release',
    drive_document_submit.reason, jsonb_build_object('attachmentId', v_file."id", 'revision', v_revision, 'name', v_file."name"));
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive_node.submitted', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'attachmentId', v_file."id", 'requestId', v_request ->> 'id'), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.submitted',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document submitted',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'attachmentId', v_file."id", 'requestId', v_request ->> 'id')
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_documents (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if jsonb_typeof(coalesce(drive_documents.filters, '{}'::jsonb)) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) order by x."document_number")
    from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_documents.tenant and x."document_status" is not null and x."archived_at" is null
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
      and (drive_documents.filters ->> 'type' is null or x."document_type" = drive_documents.filters ->> 'type')
      and (drive_documents.filters ->> 'status' is null or x."document_status" = drive_documents.filters ->> 'status')
      and (drive_documents.filters ->> 'ownerId' is null or x."document_owner_id"::text = drive_documents.filters ->> 'ownerId')
      and (coalesce((drive_documents.filters ->> 'reviewDue')::boolean, false) = false
        or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
      and (coalesce(drive_documents.filters ->> 'search', '') = ''
        or x."document_number" ilike '%' || (drive_documents.filters ->> 'search') || '%'
        or x."name" ilike '%' || (drive_documents.filters ->> 'search') || '%')
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_free_name (
  tenant   uuid,
  drive    uuid,
  parent   uuid,
  name     text,
  exclude  uuid,
  conflict text
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_ext text;
  v_base text;
  v_try text := drive_free_name.name;
  v_n integer := 1;
begin
  perform "better_supabase"."drive_lock_siblings"(drive_free_name.tenant, drive_free_name.drive, drive_free_name.parent);
  loop
    exit when not exists (
      select 1 from "better_supabase"."drive_nodes" x
      where x."tenant_id" = drive_free_name.tenant and x."parent_id" is not distinct from drive_free_name.parent and x."archived_at" is null
        and lower(x."name") = lower(v_try) and x."id" is distinct from drive_free_name.exclude
    );
    if drive_free_name.conflict <> 'rename' then
      raise exception 'another item in this folder has this name' using errcode = '23505', hint = 'DRIVE_NAME_CONFLICT';
    end if;
    if v_n = 1 then
      v_ext := coalesce(substring(drive_free_name.name from '.(\.[^.]+)$'), '');
      v_base := left(drive_free_name.name, length(drive_free_name.name) - length(v_ext));
    end if;
    v_n := v_n + 1;
    v_try := v_base || ' (' || v_n::text || ')' || v_ext;
  end loop;
  return v_try;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_get (
  node uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_get.node and x."archived_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_grant_access (
  subject_id text,
  user_id    uuid,
  action     text,
  ends_at    timestamp with time zone
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_role text := case drive_grant_access.action when 'read' then 'viewer' when 'comment' then 'editor' when 'write' then 'editor' end;
begin
  if drive_grant_access.subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_grant_access.subject_id::uuid and x."archived_at" is null;
  if not found then
    raise exception 'item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_role is null then
    raise exception 'action must be read, comment or write' using errcode = '22023', hint = 'DRIVE_ROLE_UNKNOWN';
  end if;
  if drive_grant_access.ends_at is not null and drive_grant_access.ends_at <= now() then
    delete from "better_supabase"."drive_grants" dg where dg."node_id" = v_node."id" and dg."principal_type" = 'user' and dg."principal_id" = drive_grant_access.user_id::text and dg."access_request";
    if found then
      perform "better_supabase".emit_event('drive_node.unshared', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', 'user', 'principalId', drive_grant_access.user_id::text), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.unshared',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'access request ended',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', 'user', 'principalId', drive_grant_access.user_id::text)
  );
    end if;
    return;
  end if;
  if exists (
    select 1 from "better_supabase"."drive_grants" dg
    where dg."node_id" = v_node."id" and dg."principal_type" = 'user' and dg."principal_id" = drive_grant_access.user_id::text and not dg."access_request"
      and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], dg."role"::text), 0) >= coalesce(array_position(array['viewer', 'editor', 'owner']::text[], v_role::text), 0)
      and (dg."expires_at" is null or dg."expires_at" > now())
  ) then
    return;
  end if;
  delete from "better_supabase"."drive_grants" dg where dg."node_id" = v_node."id" and dg."principal_type" = 'user' and dg."principal_id" = drive_grant_access.user_id::text;
  insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role", "expires_at", "access_request", "created_by")
  values (v_node."tenant_id", v_node."id", 'user', drive_grant_access.user_id::text, v_role, drive_grant_access.ends_at, true, auth.uid());
  perform "better_supabase".emit_event('drive_node.shared', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', 'user', 'principalId', drive_grant_access.user_id::text, 'role', v_role), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.shared',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'access request granted',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', 'user', 'principalId', drive_grant_access.user_id::text, 'role', v_role)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_hold (
  node  uuid,
  until timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_hold.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to place a legal hold' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if drive_hold.until is null or drive_hold.until <= now() then
    raise exception 'a legal hold needs an end in the future' using errcode = '22023', hint = 'DRIVE_HOLD_INVALID';
  end if;
  update "better_supabase"."drive_nodes" x set "legal_hold_expires_at" = drive_hold.until, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.hold_placed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'legalHoldUntil', v_node."legal_hold_expires_at"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.hold_placed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'held',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'legalHoldUntil', v_node."legal_hold_expires_at")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_insert_node (
  tenant   uuid,
  drive    uuid,
  parent   uuid,
  kind     text,
  name     text,
  conflict text,
  fields   jsonb,
  source   text  DEFAULT 'internal'::text
)
  RETURNS better_supabase.drive_nodes
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_parent "better_supabase"."drive_nodes"%rowtype;
  v_fields "better_supabase"."drive_nodes"%rowtype;
  v_drive uuid := drive_insert_node.drive;
  v_name text;
  v_last text;
begin
  select * into v_parent from "better_supabase"."drive_nodes" x where x."id" = drive_insert_node.parent;
  v_name := "better_supabase"."drive_free_name"(drive_insert_node.tenant, v_drive, drive_insert_node.parent, drive_insert_node.name, null, drive_insert_node.conflict);
  v_fields := jsonb_populate_record(null::"better_supabase"."drive_nodes", coalesce(drive_insert_node.fields, '{}'::jsonb));
  select max(x."rank") into v_last from "better_supabase"."drive_nodes" x
  where x."tenant_id" = drive_insert_node.tenant and x."parent_id" is not distinct from drive_insert_node.parent and x."archived_at" is null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_create"(uuid, uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text)', v_hook::oid::regproc)
        using drive_insert_node.tenant, drive_insert_node.parent, drive_insert_node.kind, v_name;
    end if;
  end;
  insert into "better_supabase"."drive_nodes" ("tenant_id", "parent_id", "kind", "name", "rank", "source", "created_by")
  values (drive_insert_node.tenant, drive_insert_node.parent, drive_insert_node.kind, v_name, case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end, drive_insert_node.source, case when drive_insert_node.source = 'request' then null else auth.uid() end)
  returning * into v_node;
  if drive_insert_node.parent is null and auth.uid() is not null then
    insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role")
    values (v_node."tenant_id", v_node."id", 'user', auth.uid()::text, 'owner')
    on conflict ("node_id", "principal_type", "principal_id") do update set "role" = excluded."role", "access_request" = false;
  end if;
  perform "better_supabase".emit_event('drive_node.created', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'kind', v_node."kind", 'name', v_node."name", 'parentId', v_node."parent_id", 'source', drive_insert_node.source), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.created',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'created',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'kind', v_node."kind", 'name', v_node."name", 'parentId', v_node."parent_id", 'source', drive_insert_node.source)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return v_node;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_label (
  node    uuid,
  tag     uuid,
  applied boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_label.node and x."archived_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to label this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if coalesce(drive_label.applied, true) then
    perform "better_supabase"."tag"(v_node."tenant_id", 'drive_node', v_node."id"::text, drive_label.tag);
  else
    perform "better_supabase"."untag"(v_node."tenant_id", 'drive_node', v_node."id"::text, drive_label.tag);
  end if;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_labeled (
  tenant    uuid,
  tag       uuid,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(t.node order by t.ord), '[]'::jsonb) from (
    select ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) as node, row_number() over (order by (x."kind" = 'folder') desc, x."rank", lower(x."name"), x."id") as ord
    from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_labeled.tenant and x."archived_at" is null
      and exists (select 1 from "better_supabase"."taggings" lg where lg."subject_type" = 'drive_node' and lg."subject_id" = x."id"::text and lg."tag_id" = drive_labeled.tag)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
    order by (x."kind" = 'folder') desc, x."rank", lower(x."name"), x."id"
    limit least(greatest(coalesce(drive_labeled.page_size, 50), 1), 200)
  ) t
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_link (
  token text,
  node  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_link_id uuid;
  v_role text;
  v_root text;
  v_expires timestamptz;
  v_tenant text;
  v_download boolean;
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select l."id", l."role", l."subject_id", l."expires_at", l."tenant_id"::text, l."download_allowed"
    into v_link_id, v_role, v_root, v_expires, v_tenant, v_download
  from "better_supabase"."share_links" l
  where l."token_hash" = encode(extensions.digest(convert_to(drive_link.token, 'utf8'), 'sha256'), 'hex')
    and l."subject_type" = 'drive_node'
    and l."revoked_at" is null
    and (l."expires_at" is null or l."expires_at" > now())
    and (l."max_uses" is null or l."use_count" < l."max_uses")
    and l."password_hash" is null;
  if v_link_id is null or v_root !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'this link does not exist or has expired' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = coalesce(drive_link.node, v_root::uuid)
    and x."tenant_id"::text = v_tenant and x."archived_at" is null;
  if not found or not (v_root::uuid = any ("better_supabase"."drive_ancestors"(v_node."id"))) then
    raise exception 'this link does not open that item' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  if v_role = 'upload' then
    raise exception 'an upload link takes files and opens nothing' using errcode = '22023', hint = 'DRIVE_LINK_ROLE_INVALID';
  end if;
  if "better_supabase"."drive_sharing"(v_node."tenant_id") ->> 'links' = 'none' then
    raise exception 'this organization has turned off share links' using errcode = '42501', hint = 'DRIVE_SHARING_DISABLED';
  end if;
  if "better_supabase"."drive_sharing"(v_node."tenant_id") ->> 'links' = 'organization' and not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = v_node."tenant_id" and mu."user_id" = auth.uid()
  ) then
    raise exception 'sign in as a member of this organization to open this link' using errcode = '42501', hint = 'DRIVE_SHARING_DISABLED';
  end if;
  v_download := coalesce(v_download, true) and not "better_supabase"."drive_download_blocked"(v_node."id");
  return jsonb_build_object(
    'link', jsonb_build_object('id', v_link_id, 'role', v_role, 'nodeId', v_root::uuid, 'expiresAt', v_expires, 'downloadAllowed', v_download),
    'node', "better_supabase"."drive_node_json"(v_node),
    'children', case when v_node."kind" = 'folder' then (
      select coalesce(jsonb_agg("better_supabase"."drive_node_json"(c.r) order by ((c.r)."kind" = 'folder') desc, (c.r)."rank", lower((c.r)."name"), (c.r)."id"), '[]'::jsonb)
      from (select y as r from "better_supabase"."drive_nodes" y where y."parent_id" = v_node."id" and y."archived_at" is null order by (y."kind" = 'folder') desc, y."rank", lower(y."name"), y."id" limit 500) c
    ) end,
    'object', case when v_download then (select jsonb_build_object('bucket', f."bucket", 'path', f."object_path", 'mimeType', f."mime_type", 'status', f."status")
      from "better_supabase"."attachments" f where f."id" = v_node."attachment_id") end,
    'previews', "better_supabase"."drive_preview_json"(v_node)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_link_upload (
  token     text,
  name      text,
  mime_type text,
  size      bigint,
  password  text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_link jsonb := "better_supabase"."resolve_share_link"(drive_link_upload.token, drive_link_upload.password);
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_folder "better_supabase"."drive_nodes"%rowtype;
  v_attachment jsonb;
  v_allowed boolean;
  v_retry integer;
begin
  if v_link is null then
    raise exception 'this link does not exist or has expired' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  if v_link ->> 'id' is null then
    return jsonb_build_object('passwordRequired', true);
  end if;
  if v_link ->> 'subjectType' is distinct from 'drive_node' or v_link ->> 'subjectId' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'this link does not exist or has expired' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  if v_link ->> 'role' is distinct from 'upload' then
    raise exception 'only an upload link takes files' using errcode = '22023', hint = 'DRIVE_LINK_ROLE_INVALID';
  end if;
  select * into v_folder from "better_supabase"."drive_nodes" x where x."id" = (v_link ->> 'subjectId')::uuid
    and x."tenant_id"::text = v_link ->> 'organizationId' and x."archived_at" is null;
  if not found or v_folder."kind" <> 'folder' then
    raise exception 'this link does not open that item' using errcode = 'P0002', hint = 'DRIVE_LINK_NOT_FOUND';
  end if;
  if "better_supabase"."drive_sharing"(v_folder."tenant_id") ->> 'links' = 'none' then
    raise exception 'this organization has turned off share links' using errcode = '42501', hint = 'DRIVE_SHARING_DISABLED';
  end if;
  if "better_supabase"."drive_sharing"(v_folder."tenant_id") ->> 'links' = 'organization' and not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = v_folder."tenant_id" and mu."user_id" = auth.uid()
  ) then
    raise exception 'sign in as a member of this organization to open this link' using errcode = '42501', hint = 'DRIVE_SHARING_DISABLED';
  end if;
  if (coalesce(v_folder."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  select h.allowed, h.retry_after into v_allowed, v_retry
  from better_supabase.hit_rate_limit('drive_link_upload', v_link ->> 'id',
    case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'drive_link_upload') then null else 20 end,
    case when exists (select 1 from "better_supabase"."rate_limit_rules" q where q."scope" = 'drive_link_upload') then null else '1 hour'::interval end) h;
  if not v_allowed then
    raise exception 'too many uploads through this link' using errcode = 'BS429', hint = 'DRIVE_LINK_RATE_LIMITED', detail = 'retry after ' || v_retry;
  end if;
  v_node := "better_supabase"."drive_insert_node"(v_folder."tenant_id", null, v_folder."id", 'file', "better_supabase"."drive_clean_name"(drive_link_upload.name), 'rename', null, 'request');
  v_attachment := "better_supabase"."create_attachment"(v_node."tenant_id", v_node."name", drive_link_upload.mime_type, drive_link_upload.size, 'drive_node', v_node."id"::text);
  return jsonb_build_object('nodeId', v_node."id", 'bucket', v_attachment ->> 'bucket', 'path', v_attachment ->> 'object_path', 'attachment', v_attachment);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_list (
  tenant    uuid,
  parent    uuid    DEFAULT NULL::uuid,
  page_size integer DEFAULT 100,
  skip      integer DEFAULT 0,
  drive     uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_list.tenant, 'drive.read'), false)) then
    raise exception 'not allowed to read this organization''s drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_list.parent is not null and not exists (
    select 1 from "better_supabase"."drive_nodes" p where p."id" = drive_list.parent and p."tenant_id" = drive_list.tenant and p."archived_at" is null
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(p."id", 'viewer'))
  ) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(("better_supabase"."drive_node_json"(c.r) || jsonb_build_object('role', "better_supabase"."drive_role"((c.r)."id"), 'readOnly', (coalesce((c.r)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((c.r)."id"), 'downloadable', "better_supabase"."drive_can_download"((c.r)."id"))) order by ((c.r)."kind" = 'folder') desc, (c.r)."rank", lower((c.r)."name"), (c.r)."id"), '[]'::jsonb)
    from (
      select x as r from "better_supabase"."drive_nodes" x
      where x."tenant_id" = drive_list.tenant and x."parent_id" is not distinct from drive_list.parent and x."archived_at" is null
        and (drive_list.parent is not null or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
      order by (x."kind" = 'folder') desc, x."rank", lower(x."name"), x."id"
      limit least(greatest(coalesce(drive_list.page_size, 100), 1), 500)
      offset greatest(coalesce(drive_list.skip, 0), 0)
    ) c
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_lock (
  node  uuid,
  until timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  note  text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_until timestamptz := coalesce(drive_lock.until, now() + interval '8 hours');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_lock.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if auth.uid() is null then
    raise exception 'not allowed to check out an item without a user' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if not "better_supabase"."drive_node_writable"(v_node."id") then
    if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
      raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
    end if;
    raise exception 'not allowed to check out this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be checked out' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if v_until <= now() or v_until > now() + interval '30 days' then
    raise exception 'a lock ends in the future and within 30 days' using errcode = '22023', hint = 'DRIVE_LOCK_INVALID';
  end if;
  if length(drive_lock.note) > 500 then
    raise exception 'a lock note is at most 500 characters' using errcode = '22023', hint = 'DRIVE_LOCK_INVALID';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  update "better_supabase"."drive_nodes" x set "locked_by" = auth.uid(), "lock_expires_at" = v_until, "lock_note" = drive_lock.note, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.locked', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_node."locked_by"::text, 'lockedUntil', v_node."lock_expires_at"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.locked',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'checked out',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_node."locked_by"::text, 'lockedUntil', v_node."lock_expires_at")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_marked (
  tenant    uuid,
  recent    boolean DEFAULT false,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(t.node order by t.marked_at desc), '[]'::jsonb) from (
    select ("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) || jsonb_build_object('starredAt', s."starred_at", 'openedAt', s."last_opened_at") as node,
      case when drive_marked.recent then s."last_opened_at" else s."starred_at" end as marked_at
    from "better_supabase"."subject_user_state" s
    join "better_supabase"."drive_nodes" x on x."id"::text = s."subject_id"
    where s."subject_type" = 'drive_node' and s."user_id" = auth.uid()
      and x."tenant_id" = drive_marked.tenant and x."archived_at" is null
      and case when drive_marked.recent then s."last_opened_at" else s."starred_at" end is not null
      and "better_supabase"."drive_can"(x."id", 'viewer')
    order by marked_at desc
    limit least(greatest(coalesce(drive_marked.page_size, 50), 1), 200)
  ) t
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_move (
  node     uuid,
  parent   uuid,
  rank     text DEFAULT NULL::text,
  conflict text DEFAULT NULL::text,
  drive    uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_previous uuid;
  v_target uuid;
  v_name text;
  v_role text;
  v_last text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_move.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to move this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if drive_move.rank is not null and drive_move.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a key from rankBetween' using errcode = '22023', hint = 'DRIVE_RANK_INVALID';
  end if;
  v_previous := v_node."parent_id";
  if drive_move.parent is null then
    if v_previous is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ("better_supabase"."drive_can"(v_node."id", 'owner') and coalesce(better_supabase.can('tenant', v_node."tenant_id", 'drive.create'), false))) then
      raise exception 'not allowed to move this item to the top of the drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
    end if;
  else
    perform "better_supabase"."drive_check_parent"(v_node."tenant_id", drive_move.parent, drive_move.drive);
    if v_node."id" = any ("better_supabase"."drive_ancestors"(drive_move.parent)) then
      raise exception 'a folder can''t move into itself or its own subfolder' using errcode = '22023', hint = 'DRIVE_MOVE_CYCLE';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_move"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_node."id", drive_move.parent;
    end if;
  end;
  if v_previous is distinct from drive_move.parent then
    v_name := "better_supabase"."drive_free_name"(v_node."tenant_id", v_target, drive_move.parent, v_node."name", v_node."id",
      case when "better_supabase"."drive_conflict"(drive_move.conflict) = 'rename' then 'rename' else 'fail' end);
    if drive_move.parent is null and auth.uid() is not null then
      v_role := "better_supabase"."drive_role"(v_node."id");
      insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role")
    values (v_node."tenant_id", v_node."id", 'user', auth.uid()::text, v_role)
    on conflict ("node_id", "principal_type", "principal_id") do update set "role" = excluded."role", "access_request" = false;
    end if;
    if drive_move.rank is null then
      select max(x."rank") into v_last from "better_supabase"."drive_nodes" x
      where x."tenant_id" = v_node."tenant_id" and x."parent_id" is not distinct from drive_move.parent and x."archived_at" is null;
    end if;
    update "better_supabase"."drive_nodes" x set "parent_id" = drive_move.parent, "name" = v_name, "rank" = coalesce(drive_move.rank, case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
    perform "better_supabase".emit_event('drive_node.moved', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'parentId', v_node."parent_id", 'previousParentId', v_previous), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.moved',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'moved',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'parentId', v_node."parent_id", 'previousParentId', v_previous)
  );
  elsif drive_move.rank is not null then
    update "better_supabase"."drive_nodes" x set "rank" = drive_move.rank, "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_move"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_node_bin_touch()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if new."archived_at" is distinct from old."archived_at" then
    new."updated_at" := now();
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_node_json (
  node better_supabase.drive_nodes
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', ($1)."id", 'organizationId', ($1)."tenant_id", 'driveId', null, 'parentId', ($1)."parent_id", 'kind', ($1)."kind", 'name', ($1)."name", 'rank', ($1)."rank", 'source', ($1)."source", 'externalId', ($1)."external_id", 'externalMetadata', ($1)."external_metadata", 'legalHoldUntil', ($1)."legal_hold_expires_at", 'lockedBy', case when ($1)."lock_expires_at" > now() then ($1)."locked_by" end, 'lockedUntil', case when ($1)."lock_expires_at" > now() then ($1)."lock_expires_at" end, 'lockNote', case when ($1)."lock_expires_at" > now() then ($1)."lock_note" end, 'downloadBlocked', ($1)."download_blocked", 'previewPages', ($1)."preview_pages", 'createdBy', ($1)."created_by", 'createdAt', ($1)."created_at", 'updatedAt', ($1)."updated_at", 'deletedAt', ($1)."archived_at", 'attachmentId', ($1)."attachment_id", 'file', (select jsonb_build_object('mimeType', fa."mime_type", 'size', fa."size", 'status', fa."status", 'uploadedAt', fa."uploaded_at") from "better_supabase"."attachments" fa where fa."id" = ($1)."attachment_id"), 'labels', (select coalesce(jsonb_agg(jsonb_build_object('id', lt."id", 'name', lt."name", 'color', lt."color") order by lt."rank" collate "C", lt."name", lt."id"), '[]'::jsonb)
      from "better_supabase"."taggings" lg join "better_supabase"."tags" lt on lt."id" = lg."tag_id"
      where lg."subject_type" = 'drive_node' and lg."subject_id" = ($1)."id"::text), 'approval', (select jsonb_build_object('id', lr."id", 'status', lr."status", 'createdAt', lr."created_at", 'decidedAt', lr."decided_at")
      from "better_supabase"."approval_requests" lr
      where lr."subject_type" = 'drive_node' and lr."subject_id" = ($1)."id"::text and lr."action" = 'approve'
        and lr."payload" ->> 'attachmentId' = ($1)."attachment_id"::text
      order by lr."created_at" desc, lr."id" limit 1), 'document', case when ($1)."document_status" is null then null else jsonb_build_object('number', ($1)."document_number", 'type', ($1)."document_type", 'status', ($1)."document_status", 'ownerId', ($1)."document_owner_id", 'effectiveVersionId', ($1)."effective_version_id", 'effectiveVersion', (select r."number" from "better_supabase"."versions" r where r."id" = ($1)."effective_version_id"), 'effectiveAttachmentId', (select (r."content" ->> 'attachmentId')::uuid from "better_supabase"."versions" r where r."id" = ($1)."effective_version_id"), 'effectiveFrom', ($1)."effective_at", 'reviewIntervalMonths', ($1)."review_interval_months", 'nextReviewOn', ($1)."next_review_on", 'reviewDue', coalesce(($1)."document_status" = 'effective' and ($1)."next_review_on" <= current_date, false), 'effectiveOnly', not "better_supabase"."drive_can"(($1)."id", 'editor')) end)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_open (
  node uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_open.node and x."archived_at" is null;
  if not found or auth.uid() is null or not "better_supabase"."drive_can"(v_node."id", 'viewer') then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  insert into "better_supabase"."subject_user_state" ("subject_type", "subject_id", "user_id", "last_opened_at")
  values ('drive_node', v_node."id"::text, auth.uid(), now())
  on conflict ("subject_type", "subject_id", "user_id")
  do update set "last_opened_at" = now();
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_previews (
  node uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_previews.node and x."archived_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'a folder has no previews' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  return "better_supabase"."drive_preview_json"(v_node);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_release_hold (
  node uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_release_hold.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to release a legal hold' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  update "better_supabase"."drive_nodes" x set "legal_hold_expires_at" = null, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.hold_released', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.hold_released',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'released',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_rename (
  node     uuid,
  name     text,
  conflict text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_previous text;
  v_name text := "better_supabase"."drive_clean_name"(drive_rename.name);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_rename.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to rename this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if v_name = v_node."name" then
    return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
  end if;
  v_name := "better_supabase"."drive_free_name"(v_node."tenant_id", null, v_node."parent_id", v_name, v_node."id",
    case when "better_supabase"."drive_conflict"(drive_rename.conflict) = 'rename' then 'rename' else 'fail' end);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_rename"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_node."id", v_name;
    end if;
  end;
  v_previous := v_node."name";
  update "better_supabase"."drive_nodes" x set "name" = v_name, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.renamed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'name', v_node."name", 'previousName', v_previous), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.renamed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'renamed',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'name', v_node."name", 'previousName', v_previous)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_rename"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_node."id";
    end if;
  end;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_request_approval (
  node       uuid,
  attachment uuid DEFAULT NULL::uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
  v_revision integer;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_request_approval.node and x."archived_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to ask for approval of this file' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be approved' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  select * into v_file from "better_supabase"."attachments" f
  where f."id" = coalesce(drive_request_approval.attachment, v_node."attachment_id")
    and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
    and f."uploaded_at" is not null;
  if not found then
    raise exception 'that version of the file was not found' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  select r."number" into v_revision from "better_supabase"."versions" r
  where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
    and r."content" ->> 'attachmentId' = v_file."id"::text
  order by r."number" limit 1;
  return "better_supabase"."request_approval"(v_node."tenant_id", 'drive_node', v_node."id"::text, 'approve',
    drive_request_approval.reason, jsonb_build_object('attachmentId', v_file."id", 'revision', v_revision, 'name', v_file."name"))
    || jsonb_build_object('attachmentId', v_file."id", 'revision', v_revision, 'current', v_file."id" = v_node."attachment_id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_request_files (
  folder     uuid,
  expires_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_uses   integer                  DEFAULT NULL::integer,
  password   text                     DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_request_files.folder and x."archived_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return "better_supabase"."create_share_link"(
    tenant => v_node."tenant_id", subject_type => 'drive_node', subject_id => v_node."id"::text, role => 'upload',
    expires_at => drive_request_files.expires_at, max_uses => drive_request_files.max_uses, password => drive_request_files.password);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_restore (
  item     uuid,
  conflict text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_root "better_supabase"."trash_items"%rowtype;
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_name text;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r.* into v_root from "better_supabase"."trash_items" i
  join "better_supabase"."trash_items" r on r."batch_id" = i."batch_id" and r."depth" = 0
  where i."id" = drive_restore.item and r."subject_type" = 'drive_node';
  if not found then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_root."subject_id"::uuid;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to restore this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if v_node."parent_id" is not null and exists (
    select 1 from "better_supabase"."drive_nodes" p where p."id" = v_node."parent_id" and p."archived_at" is not null
  ) then
    raise exception 'restore the folder this item was in first' using errcode = '22023', hint = 'DRIVE_PARENT_TRASHED';
  end if;
  v_name := "better_supabase"."drive_free_name"(v_node."tenant_id", null, v_node."parent_id", v_node."name", v_node."id", "better_supabase"."drive_conflict"(drive_restore.conflict));
  if v_name <> v_node."name" then
    update "better_supabase"."drive_nodes" x set "name" = v_name where x."id" = v_node."id";
  end if;
  v_count := "better_supabase"."trash_restore_batch"(v_root."batch_id");
  delete from "better_supabase"."trash_items" where "batch_id" = v_root."batch_id";
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  return jsonb_build_object('id', v_root."id", 'batchId', v_root."batch_id", 'count', v_count, 'node', "better_supabase"."drive_node_json"(v_node));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_restore_revision (
  node    uuid,
  version uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_content jsonb;
  v_file "better_supabase"."attachments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_restore_revision.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to change this file' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  select r."content" into v_content from "better_supabase"."versions" r
  where r."id" = drive_restore_revision.version
    and r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text;
  if v_content is null or v_content ->> 'attachmentId' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'revision not found' using errcode = 'P0002', hint = 'DRIVE_REVISION_NOT_FOUND';
  end if;
  select * into v_file from "better_supabase"."attachments" f where f."id" = (v_content ->> 'attachmentId')::uuid;
  if not found then
    raise exception 'the revision''s file was pruned' using errcode = 'P0002', hint = 'DRIVE_REVISION_NOT_FOUND';
  end if;
  update "better_supabase"."drive_nodes" x set "attachment_id" = v_file."id", "preview_pages" = null, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase"."version_insert"(v_node."tenant_id", 'drive_node', v_node."id"::text,
    v_content, v_file."bucket" || '/' || v_file."object_path", null, 'restore', false, auth.uid());
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_retention_sweep (
  tenant     uuid    DEFAULT NULL::uuid,
  batch_size integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node uuid;
  v_binned integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'not allowed to sweep retention' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  for v_node in
    select x."id" from "better_supabase"."drive_nodes" x
    where (drive_retention_sweep.tenant is null or x."tenant_id" = drive_retention_sweep.tenant) and x."archived_at" is null
      and exists (
        select 1 from "better_supabase"."taggings" lg
        join "better_supabase"."tags" lt on lt."id" = lg."tag_id"
        where lg."subject_type" = 'drive_node' and lg."subject_id" = x."id"::text
          and "better_supabase"."retention_for"("better_supabase"."drive_retention_kind"(lt."name"), x."tenant_id"::text) is not null
          and coalesce(x."updated_at", x."created_at") < now() - "better_supabase"."retention_for"("better_supabase"."drive_retention_kind"(lt."name"), x."tenant_id"::text)
          and not "better_supabase"."is_held"("better_supabase"."drive_retention_kind"(lt."name"), x."tenant_id"::text)
      )
      and not "better_supabase"."drive_node_held"(x."id")
    order by coalesce(x."updated_at", x."created_at"), x."id"
    limit least(greatest(coalesce(drive_retention_sweep.batch_size, 100), 1), 1000)
  loop
    begin
      perform "better_supabase"."drive_trash"(v_node);
      v_binned := v_binned + 1;
    exception when insufficient_privilege then
      null;
    end;
  end loop;
  return v_binned;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_revisions (
  node uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_revisions.node and x."archived_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id", 'number', r."number", 'label', r."label", 'source', r."source",
      'attachmentId', r."content" ->> 'attachmentId', 'name', r."content" ->> 'name',
      'mimeType', r."content" ->> 'mimeType', 'size', (r."content" ->> 'size')::bigint,
      'current', r."content" ->> 'attachmentId' = v_node."attachment_id"::text,
      'createdBy', r."created_by", 'createdAt', r."created_at"
    ) order by r."number" desc), '[]'::jsonb)
    from "better_supabase"."versions" r
    where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_search (
  tenant    uuid,
  query     text,
  page_size integer DEFAULT 25
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_like text := '%' || replace(replace(replace(btrim(coalesce(drive_search.query, '')), '\', '\\'), '%', '\%'), '_', '\_') || '%';
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_search.tenant, 'drive.read'), false)) then
    raise exception 'not allowed to read this organization''s drive' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if btrim(coalesce(drive_search.query, '')) = '' then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(("better_supabase"."drive_node_json"(c.r) || jsonb_build_object('role', "better_supabase"."drive_role"((c.r)."id"), 'readOnly', (coalesce((c.r)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((c.r)."id"), 'downloadable', "better_supabase"."drive_can_download"((c.r)."id"))) order by (c.r)."kind" <> 'folder', (c.r)."name", (c.r)."id"), '[]'::jsonb)
    from (
      select x as r from "better_supabase"."drive_nodes" x
      where x."tenant_id" = drive_search.tenant and x."archived_at" is null
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
        and (x."name" ilike v_like escape '\'
      or exists (select 1 from "better_supabase"."drive_node_texts" t where t."node_id" = x."id" and t."content" ilike v_like escape '\'))
      order by x."kind" <> 'folder', x."name", x."id"
      limit least(greatest(coalesce(drive_search.page_size, 25), 1), 100)
    ) c
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_set_download_blocked (
  target_type text,
  target_id   uuid,
  blocked     boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if drive_set_download_blocked.target_type is null or drive_set_download_blocked.target_type not in ('node') then
    raise exception 'target_type must be node' using errcode = '22023', hint = 'DRIVE_TARGET_INVALID';
  end if;
  if drive_set_download_blocked.blocked is null then
    raise exception 'blocked must be true or false' using errcode = '22023', hint = 'DRIVE_TARGET_INVALID';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_set_download_blocked.target_id and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to change downloads of this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if v_node."download_blocked" is distinct from drive_set_download_blocked.blocked then
    update "better_supabase"."drive_nodes" x set "download_blocked" = drive_set_download_blocked.blocked, "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
    perform "better_supabase".emit_event('drive_node.download_blocked_changed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'downloadBlocked', v_node."download_blocked"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.download_blocked_changed',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'download block changed',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'downloadBlocked', v_node."download_blocked")
  );
  end if;
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_share (
  node           uuid,
  principal_type text,
  principal_id   text,
  role           text,
  expires_at     timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_type text := lower(drive_share.principal_type);
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_share.node and x."archived_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ("better_supabase"."drive_can"(v_node."id", 'owner') and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], drive_share.role::text), 0) <= coalesce(array_position(array['viewer', 'editor', 'owner']::text[], "better_supabase"."drive_role"(v_node."id")::text), 0))) then
    raise exception 'not allowed to share this item with that role' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if coalesce(array_position(array['viewer', 'editor', 'owner']::text[], drive_share.role::text), 0) = 0 and drive_share.role is distinct from 'contributor' then
    raise exception 'role must be one of viewer, editor, owner, contributor' using errcode = '22023', hint = 'DRIVE_ROLE_UNKNOWN';
  end if;
  if drive_share.role = 'contributor' and v_node."kind" <> 'folder' then
    raise exception 'the upload role is for folders' using errcode = '22023', hint = 'DRIVE_ROLE_UNKNOWN', detail = '{"reason":"upload role is for folders"}';
  end if;
  if v_type not in ('user', 'team', 'role') or drive_share.principal_id is null then
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'DRIVE_PRINCIPAL_INVALID';
  end if;
  if (v_type = 'user' and (drive_share.principal_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or not exists (
      select 1 from "public"."memberships" mu
      where mu."organization_id" = v_node."tenant_id" and mu."user_id" = drive_share.principal_id::uuid
    )))
    or (v_type = 'team' and not exists (select 1 from "better_supabase"."teams" t where t."id"::text = drive_share.principal_id and t."tenant_id" = v_node."tenant_id")) then
    raise exception 'no member or team of this organization has that id' using errcode = 'P0002', hint = 'DRIVE_PRINCIPAL_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_drive_node_share"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using v_node."id", v_type, drive_share.principal_id, drive_share.role;
    end if;
  end;
  delete from "better_supabase"."drive_grants" dg where dg."node_id" = v_node."id" and dg."principal_type" = v_type and dg."principal_id" = drive_share.principal_id;
  insert into "better_supabase"."drive_grants" ("tenant_id", "node_id", "principal_type", "principal_id", "role", "expires_at", "created_by")
  values (v_node."tenant_id", v_node."id", v_type, drive_share.principal_id, drive_share.role, drive_share.expires_at, auth.uid())
  returning "id" into v_id;
  perform "better_supabase".emit_event('drive_node.shared', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.shared',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'shared',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_drive_node_share"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_node."id", v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'nodeId', v_node."id", 'principalType', v_type, 'principalId', drive_share.principal_id, 'role', drive_share.role, 'expiresAt', drive_share.expires_at, 'inherited', false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_shared (
  tenant    uuid,
  page_size integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  return (
  select coalesce(jsonb_agg(("better_supabase"."drive_node_json"(c.r) || jsonb_build_object('role', "better_supabase"."drive_role"((c.r)."id"), 'readOnly', (coalesce((c.r)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((c.r)."id"), 'downloadable', "better_supabase"."drive_can_download"((c.r)."id"))) order by (c.r)."name", (c.r)."id"), '[]'::jsonb)
  from (
    select x as r from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_shared.tenant and x."archived_at" is null
      and auth.uid() is not null
      and exists (
        select 1 from "better_supabase"."drive_grants" dg
        where dg."node_id" = x."id" and (dg."expires_at" is null or dg."expires_at" > now())
          and ((dg."principal_type" = 'user' and dg."principal_id" = auth.uid()::text)
      or (dg."principal_type" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = dg."principal_id"::text and tm."user_id" = auth.uid()))
      or (dg."principal_type" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = x."tenant_id" and mr."user_id" = auth.uid() and mr."role"::text = dg."principal_id")))
      )
      and (x."parent_id" is null or not "better_supabase"."drive_can"(x."parent_id", 'viewer'))
      and "better_supabase"."drive_can"(x."id", 'viewer')
    order by x."name", x."id"
    limit least(greatest(coalesce(drive_shared.page_size, 100), 1), 500)
  ) c
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_text_source (
  node       uuid DEFAULT NULL::uuid,
  attachment uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('nodeId', s."id", 'organizationId', s."tenant_id", 'name', s."name",
    'attachmentId', f."id", 'bucket', f."bucket", 'path', f."object_path", 'mimeType', f."mime_type",
    'size', f."size", 'status', f."status")
  from "better_supabase"."drive_nodes" s
  join "better_supabase"."attachments" f on f."id" = s."attachment_id"
  where s."id" = coalesce(drive_text_source.node, (select x."id" from "better_supabase"."drive_nodes" x where x."attachment_id" = drive_text_source.attachment limit 1))
    and (drive_text_source.attachment is null or s."attachment_id" = drive_text_source.attachment)
    and s."kind" = 'file' and s."archived_at" is null
    and f."uploaded_at" is not null
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_trash (
  node uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_batch uuid := gen_random_uuid();
  v_count integer := 0;
  v_child record;
  v_id uuid;
  v_locked "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_trash.node and x."archived_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to move this item to the bin' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if "better_supabase"."drive_node_held"(v_node."id") then
    raise exception 'this item is under a legal hold' using errcode = '42501', hint = 'DRIVE_HELD';
  end if;
  select * into v_locked from "better_supabase"."drive_nodes" lk
  where lk."id" in (select s.node_id from "better_supabase"."drive_subtree"(v_node."id") s)
    and (lk."lock_expires_at" > now() and lk."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
  limit 1;
  if found then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_locked."locked_by", 'lockedUntil', v_locked."lock_expires_at")::text;
  end if;
  for v_child in
    select s.node_id, s.depth from "better_supabase"."drive_subtree"(v_node."id") s
    join "better_supabase"."drive_nodes" x on x."id" = s.node_id
    where x."archived_at" is null
    order by s.depth
  loop
    v_count := v_count + "better_supabase"."trash_cascade"(v_node."tenant_id", 'drive_node', v_child.node_id::text, v_batch, v_child.depth, auth.uid());
  end loop;
  select i."id" into v_id from "better_supabase"."trash_items" i
  where i."subject_type" = 'drive_node' and i."subject_id" = v_node."id"::text;
  return jsonb_build_object('id', v_id, 'batchId', v_batch, 'count', v_count);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_unlock (
  node  uuid,
  force boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_holder uuid;
  v_forced boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_unlock.node and x."archived_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."lock_expires_at" is null or v_node."lock_expires_at" <= now() then
    if v_node."locked_by" is not null then
      update "better_supabase"."drive_nodes" x set "locked_by" = null, "lock_expires_at" = null, "lock_note" = null
      where x."id" = v_node."id"
      returning * into v_node;
    end if;
    return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
  end if;
  v_holder := v_node."locked_by";
  if v_holder is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    if not coalesce(drive_unlock.force, false) then
      raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
    end if;
    if not "better_supabase"."drive_can"(v_node."id", 'owner') then
      raise exception 'not allowed to break someone else''s lock' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
    end if;
    v_forced := true;
  end if;
  update "better_supabase"."drive_nodes" x set "locked_by" = null, "lock_expires_at" = null, "lock_note" = null, "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  perform "better_supabase".emit_event('drive_node.unlocked', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_holder::text, 'forced', v_forced), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.unlocked',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'checked in',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'lockedBy', v_holder::text, 'forced', v_forced)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_unshare (
  node           uuid,
  principal_type text,
  principal_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_type text := lower(drive_unshare.principal_type);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_unshare.node and x."archived_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to change who this item is shared with' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  delete from "better_supabase"."drive_grants" dg where dg."node_id" = v_node."id"
    and dg."principal_type" = v_type and dg."principal_id" = drive_unshare.principal_id;
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('drive_node.unshared', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_unshare.principal_id), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive_node.unshared',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'unshared',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', v_type, 'principalId', drive_unshare.principal_id)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_upload_revision (
  node      uuid,
  mime_type text,
  size      bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_attachment jsonb;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_upload_revision.node and x."archived_at" is null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer') or "better_supabase"."drive_uploaded_own"(v_node."id")) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor') or "better_supabase"."drive_uploaded_own"(v_node."id")) then
    raise exception 'not allowed to change this file' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."lock_expires_at" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."lock_expires_at")::text;
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'a folder has no content' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  v_attachment := "better_supabase"."create_attachment"(v_node."tenant_id", v_node."name", drive_upload_revision.mime_type, drive_upload_revision.size, 'drive_node', v_node."id"::text);
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    return jsonb_build_object('id', v_node."id", 'attachment', v_attachment);
  end if;
  return jsonb_build_object('node', "better_supabase"."drive_node_json"(v_node), 'attachment', v_attachment);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_uploaded_own (
  node uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce((
    select x."kind" = 'file' and x."parent_id" is not null
      and x."created_by" = auth.uid() and "better_supabase"."drive_can_upload"(x."parent_id")
    from "better_supabase"."drive_nodes" x where x."id" = drive_uploaded_own.node and x."archived_at" is null
  ), false)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.edit_inbox_message (
  message uuid,
  body    text    DEFAULT NULL::text,
  remove  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_msg "better_supabase"."messages"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select m.* into v_msg from "better_supabase"."messages" m
  join "better_supabase"."inbox_message_details" d on d."message_id" = m."id"
  where m."id" = edit_inbox_message.message
  for update of m;
  if not found then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_msg."author_id" is not null and coalesce(v_msg."author_id" = (select auth.uid()), false))) then
    raise exception 'only the author edits a message' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if v_msg."archived_at" is not null then
    raise exception 'message is deleted' using errcode = '22023', hint = 'MESSAGE_DELETED';
  end if;
  if length(coalesce(edit_inbox_message.body, '')) > 20000 then
    raise exception 'a message is at most 20000 characters' using errcode = '22023', hint = 'INBOX_MESSAGE_TOO_LONG';
  end if;
  update "better_supabase"."messages" set
    "body" = case when coalesce(remove, false) then '' else coalesce(edit_inbox_message.body, "body") end,
    "archived_at" = case when coalesce(remove, false) then now() end,
    "edited_at" = case when coalesce(remove, false) then "edited_at" else now() end
  where "id" = v_msg."id";
  perform "better_supabase"."index_record_mentions"(v_msg."id");
  if coalesce(remove, false) then
    delete from "better_supabase"."attachments" x where x."subject_type" = 'message' and x."subject_id" = v_msg."id"::text;
  end if;
  return "better_supabase"."inbox_messages_json"(array[v_msg."id"]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.edit_message (
  message uuid,
  body    text,
  attrs   jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
  v_parsed jsonb := "better_supabase"."parse_mentions"(edit_message.body);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = edit_message.message and m."author_id" = auth.uid() and m."archived_at" is null
    and "better_supabase"."can_conversation"(m."conversation_id", 'read');
  if not found then
    raise exception 'no message of yours has this id' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if exists (
    select 1 from "better_supabase"."conversations" c
    where c."id" = v_msg."conversation_id"
      and c."access" = 'subject' and c."subject_type" in ('drive_node')
  ) and not "better_supabase"."can_conversation"(v_msg."conversation_id", 'send') then
    raise exception 'not allowed to comment on this record' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if v_msg."sent_at" is not null and not (true) then
    raise exception 'this message can no longer be edited' using errcode = '55000', hint = 'MESSAGING_EDIT_CLOSED';
  end if;
  if nullif(trim(coalesce(edit_message.body, '')), '') is null then
    raise exception 'a message needs a body' using errcode = '23502', hint = 'MESSAGING_BODY_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_message_edit"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using edit_message.message, edit_message.body;
    end if;
  end;
  insert into "better_supabase"."message_edits" ("tenant_id", "message_id", "body", "document", "edited_by")
  values (v_msg."tenant_id", v_msg."id", v_msg."body", v_msg."document", auth.uid());
  begin
    update "better_supabase"."messages" m set
      "body" = edit_message.body,
      "document" = case when edit_message.attrs ? 'document' then edit_message.attrs -> 'document' else m."document" end,
      "mentions" = array(
        select distinct x from (
          select (jsonb_array_elements_text(coalesce(edit_message.attrs -> 'mentions', '[]'::jsonb)))::uuid as x
          union
          select (jsonb_array_elements_text(v_parsed -> 'users'))::uuid
        ) s
      ),
      "edited_at" = now()
    where m."id" = v_msg."id"
    returning * into v_msg;
  exception when check_violation or invalid_text_representation then
    raise exception 'a message field has an invalid value' using errcode = '22023', hint = 'MESSAGING_MESSAGE_INVALID';
  end;
  if v_msg."sent_at" is not null then
    perform "better_supabase"."index_record_mentions"(v_msg."id");
    perform "better_supabase".emit_event('message.edited', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text)
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_message_edit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_msg."id";
    end if;
  end;
  return "better_supabase"."messaging_messages_json"(array[v_msg."id"]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.evaluate_segment (
  segment uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."segments";
  v_fields jsonb;
  v_now timestamptz := now();
  v_ids text[];
  v_entered text[];
  v_left text[];
  v_id text;
begin
  select * into v_row from "better_supabase"."segments" x where x."id" = evaluate_segment.segment for update;
  if v_row."id" is null then
    return null;
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_row."subject_type");
  if v_row."subject_type" = 'message' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."messages" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'conversation' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."conversations" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'channel' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."channels" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'company' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."companies" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'person' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."people" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'deal' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."deals" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'course' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."courses" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'post' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."posts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'activity' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."activities" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'quote' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."quotes" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_item' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_items" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'employee' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."employees" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'invoice' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."invoices" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'ledger_account' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."ledger_accounts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'product' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."products" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'product_variant' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."product_variants" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'rfq' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."rfqs" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'till' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."tills" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'order' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."orders" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'calendar_event' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."calendar_events" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'booking' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."bookings" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'asset' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."assets" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'asset_location' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."asset_locations" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'lease' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."leases" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'expense_report' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."expense_reports" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'expense_line' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."expense_lines" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'donation_fund' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."donation_funds" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_order' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_orders" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'shipment' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."shipments" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'contract' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."contracts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'control' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."controls" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'compliance_policy' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."compliance_policies" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'qualification_type' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."qualification_types" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'risk' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."risks" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'case' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."cases" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'inspection' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."inspections" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'inspection_program' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."inspection_programs" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'inspection_finding' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."inspection_findings" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'form' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."forms" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'meeting' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."meetings" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'meeting_decision' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."meeting_decisions" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'maintenance_plan' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."maintenance_plans" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'dam_usage_right' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."dam_usage_rights" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'lims_sample' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."lims_samples" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'tax_code' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."tax_codes" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'production_order' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."production_orders" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_center' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_centers" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'bank_account' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."bank_accounts" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'care_plan' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."care_plans" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'incident' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."incidents" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'content_entry' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."content_entries" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'document' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."documents" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'customer' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."customers" s
      where s."organization_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'drive_node' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."drive_nodes" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'application' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."applications" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'change_request' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."change_requests" s
      where s."organization_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'project' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."projects" s
      where s."organization_id" = v_row."tenant_id" and s."deleted_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'task' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."tasks" s
      where s."organization_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  else
    raise exception 'The segment''s subject type is not registered in config.subjects' using errcode = '22023', hint = 'SEGMENT_SUBJECT_UNKNOWN';
  end if;
  if cardinality(v_ids) > 10000 then
    raise exception 'A segment holds at most 10000 records; narrow its conditions' using errcode = '54000', hint = 'SEGMENT_TOO_LARGE';
  end if;
  with gone as (
    delete from "better_supabase"."segment_members" y
    where y."segment_id" = v_row."id" and not (y."subject_id" = any (v_ids))
    returning y."subject_id" as id
  ), added as (
    insert into "better_supabase"."segment_members" ("segment_id", "tenant_id", "subject_id", "entered_at")
    select v_row."id", v_row."tenant_id", z, v_now from unnest(v_ids) z
    on conflict do nothing
    returning "subject_id" as id
  )
  select coalesce((select array_agg(g.id order by g.id) from gone g), '{}'),
    coalesce((select array_agg(a.id order by a.id) from added a), '{}')
  into v_left, v_entered;
  foreach v_id in array v_entered loop
    perform "better_supabase".emit_event('segment.entered', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, 'segment.entered:' || v_row."id"::text || ':' || v_id || ':' || extract(epoch from v_now)::text, 'better-supabase/segments');
  end loop;
  foreach v_id in array v_left loop
    perform "better_supabase".emit_event('segment.left', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, 'segment.left:' || v_row."id"::text || ':' || v_id || ':' || extract(epoch from v_now)::text, 'better-supabase/segments');
  end loop;
  update "better_supabase"."segments" x set "member_count" = cardinality(v_ids), "refreshed_at" = v_now
  where x."id" = v_row."id";
  return jsonb_build_object('entered', cardinality(v_entered), 'left', cardinality(v_left), 'memberCount', cardinality(v_ids));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_file_allowed (
  bucket      text,
  object_name text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return exists (
    select 1 from "better_supabase"."attachments" a
    join "better_supabase"."messages" m on a."subject_type" = 'message' and m."id"::text = a."subject_id"
    join "better_supabase"."inbox_message_details" d on d."message_id" = m."id"
    where a."bucket" = inbox_file_allowed.bucket and a."object_path" = inbox_file_allowed.object_name
      and a."status" = 'clean'
      and m."archived_at" is null
      and "better_supabase"."inbox_conversation_allowed"(d."conversation_id"::text)
      and (m."kind" = 'message' or "better_supabase"."inbox_note_readable"(d."conversation_id"))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.index_record_mentions (
  message uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  delete from "better_supabase"."message_record_mentions" x where x."message_id" = index_record_mentions.message;
  insert into "better_supabase"."message_record_mentions" ("tenant_id", "message_id", "conversation_id", "subject_type", "subject_id", "created_at")
  select m."tenant_id", m."id", m."conversation_id", r.subject_type, r.subject_id, m."sent_at"
  from "better_supabase"."messages" m
  cross join lateral (
    select s ->> 'type' as subject_type, s ->> 'id' as subject_id
    from jsonb_array_elements("better_supabase"."parse_mentions"(m."body") -> 'subjects') s
    where s ->> 'type' = any ("better_supabase"."subject_types"())
    limit 20
  ) r
  where m."id" = index_record_mentions.message
    and m."sent_at" is not null and m."archived_at" is null
  on conflict do nothing;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_activity (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50,
  sources      text[]                   DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
  v_table text;
begin
  if list_activity.subject_id is not null and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,till,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[])
    and not "better_supabase"."activity_subject_readable"(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;
  end if;
  if list_activity.subject_id is not null then
    v_table := case list_activity.subject_type
      when 'message' then 'better_supabase.messages'
      when 'conversation' then 'better_supabase.conversations'
      when 'channel' then 'better_supabase.channels'
      when 'company' then 'better_supabase.companies'
      when 'person' then 'better_supabase.people'
      when 'deal' then 'better_supabase.deals'
      when 'course' then 'better_supabase.courses'
      when 'post' then 'better_supabase.posts'
      when 'activity' then 'better_supabase.activities'
      when 'quote' then 'better_supabase.quotes'
      when 'work_item' then 'better_supabase.work_items'
      when 'employee' then 'better_supabase.employees'
      when 'invoice' then 'better_supabase.invoices'
      when 'ledger_account' then 'better_supabase.ledger_accounts'
      when 'product' then 'better_supabase.products'
      when 'product_variant' then 'better_supabase.product_variants'
      when 'rfq' then 'better_supabase.rfqs'
      when 'till' then 'better_supabase.tills'
      when 'order' then 'better_supabase.orders'
      when 'calendar_event' then 'better_supabase.calendar_events'
      when 'booking' then 'better_supabase.bookings'
      when 'asset' then 'better_supabase.assets'
      when 'asset_location' then 'better_supabase.asset_locations'
      when 'lease' then 'better_supabase.leases'
      when 'expense_report' then 'better_supabase.expense_reports'
      when 'expense_line' then 'better_supabase.expense_lines'
      when 'donation_fund' then 'better_supabase.donation_funds'
      when 'work_order' then 'better_supabase.work_orders'
      when 'shipment' then 'better_supabase.shipments'
      when 'contract' then 'better_supabase.contracts'
      when 'control' then 'better_supabase.controls'
      when 'compliance_policy' then 'better_supabase.compliance_policies'
      when 'qualification_type' then 'better_supabase.qualification_types'
      when 'risk' then 'better_supabase.risks'
      when 'case' then 'better_supabase.cases'
      when 'inspection' then 'better_supabase.inspections'
      when 'inspection_program' then 'better_supabase.inspection_programs'
      when 'inspection_finding' then 'better_supabase.inspection_findings'
      when 'form' then 'better_supabase.forms'
      when 'meeting' then 'better_supabase.meetings'
      when 'meeting_decision' then 'better_supabase.meeting_decisions'
      when 'maintenance_plan' then 'better_supabase.maintenance_plans'
      when 'dam_usage_right' then 'better_supabase.dam_usage_rights'
      when 'lims_sample' then 'better_supabase.lims_samples'
      when 'tax_code' then 'better_supabase.tax_codes'
      when 'production_order' then 'better_supabase.production_orders'
      when 'work_center' then 'better_supabase.work_centers'
      when 'bank_account' then 'better_supabase.bank_accounts'
      when 'care_plan' then 'better_supabase.care_plans'
      when 'incident' then 'better_supabase.incidents'
      when 'content_entry' then 'better_supabase.content_entries'
      when 'document' then 'better_supabase.documents'
      when 'customer' then 'public.customers'
      when 'drive_node' then 'better_supabase.drive_nodes'
      when 'application' then 'better_supabase.applications'
      when 'change_request' then 'public.change_requests'
      when 'project' then 'public.projects'
      when 'task' then 'public.tasks'
    end;
  end if;
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."timeline_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
      and not ((y."type" = 'status.changed' and list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,till,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[])
      and list_activity.subject_type = any ('{work_item,change_request,drive_node}'::text[])
      and (list_activity.sources is null or 'transition' = any (list_activity.sources)))
        or (y."type" in ('message.sent', 'comment.posted') and list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,till,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[])
      and (list_activity.sources is null or 'message' = any (list_activity.sources))))
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', l."id"::text, 'organization_id', l."organization_id", 'event_id', null::text, 'type', coalesce(l."event_type", 'audit.' || l."op"), 'actor_id', l."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', l."summary", 'data', jsonb_strip_nulls(jsonb_build_object('op', l."op", 'changed', to_jsonb(l."changed"), 'table', l."table_name")), 'occurred_at', l."occurred_at", 'source', 'audit') as entry,
      l."occurred_at" as at, l."id"::text as id
    from "better_supabase"."audit_events" l
    where v_table is not null
      and (list_activity.sources is null or 'audit' = any (list_activity.sources))
      and l."table_name" = v_table
      and l."record_id" = list_activity.subject_id
      and l."organization_id" = list_activity.tenant
      and (list_activity.before is null or l."occurred_at" < list_activity.before)
    order by l."occurred_at" desc, l."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', r."id"::text, 'organization_id', r."tenant_id", 'event_id', null::text, 'type', 'run.' || r."status", 'actor_id', r."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', null::text, 'data', jsonb_strip_nulls(jsonb_build_object('runId', r."id", 'definition', r."definition", 'engine', r."engine", 'status', r."status", 'mode', r."mode", 'error', r."error"::text, 'completedAt', r."completed_at")), 'occurred_at', r."created_at", 'source', 'run') as entry,
      r."created_at" as at, r."id"::text as id
    from "better_supabase"."workflow_runs" r
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,till,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[])
      and (list_activity.sources is null or 'run' = any (list_activity.sources))
      and r."tenant_id" = list_activity.tenant
      and r."subject_type" = list_activity.subject_type
      and r."subject_id" = list_activity.subject_id
      and (list_activity.before is null or r."created_at" < list_activity.before)
    order by r."created_at" desc, r."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', h."id"::text, 'organization_id', h."tenant_id", 'event_id', null::text, 'type', 'status.changed', 'actor_id', h."actor_user_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', null::text, 'data', jsonb_strip_nulls(jsonb_build_object('from', h."from_status"::text, 'to', h."to_status"::text, 'reason', h."reason")), 'occurred_at', h."created_at", 'source', 'transition') as entry,
      h."created_at" as at, h."id"::text as id
    from "better_supabase"."status_history" h
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,till,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[])
      and list_activity.subject_type = any ('{work_item,change_request,drive_node}'::text[])
      and (list_activity.sources is null or 'transition' = any (list_activity.sources))
      and h."tenant_id" = list_activity.tenant
      and h."subject_type" = list_activity.subject_type
      and h."subject_id" = list_activity.subject_id
      and (list_activity.before is null or h."created_at" < list_activity.before)
    order by h."created_at" desc, h."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', m."id"::text, 'organization_id', m."tenant_id", 'event_id', null::text, 'type', case when c."kind" = 'subject' then 'comment.posted' else 'message.sent' end, 'actor_id', m."author_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', left(m."body", 280), 'data', jsonb_strip_nulls(jsonb_build_object('messageId', m."id", 'conversationId', m."conversation_id", 'threadId', m."thread_id", 'kind', m."kind"::text)), 'occurred_at', m."sent_at", 'source', 'message') as entry,
      m."sent_at" as at, m."id"::text as id
    from "better_supabase"."messages" m
    join "better_supabase"."conversations" c on c."id" = m."conversation_id"
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,till,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[])
      and (list_activity.sources is null or 'message' = any (list_activity.sources))
      and c."tenant_id" = list_activity.tenant
      and c."subject_type" = list_activity.subject_type
      and c."subject_id" = list_activity.subject_id
      and m."sent_at" is not null
      and m."archived_at" is null
      and (list_activity.before is null or m."sent_at" < list_activity.before)
    order by m."sent_at" desc, m."id" desc
    limit v_limit)
    union all
    (select d.entry, d.at, d.id
    from "better_supabase"."activity_subject_deliveries"(list_activity.tenant, list_activity.subject_type, list_activity.subject_id, list_activity.before, v_limit) d
    where list_activity.subject_id is not null
      and (list_activity.sources is null or 'delivery' = any (list_activity.sources)))
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  if list_activity.subject_id is not null and jsonb_array_length(v_rows) > 0 then
    perform "better_supabase"."record_subject_read"(list_activity.subject_type, list_activity.subject_id, null, 'timeline', 'list_activity');
  end if;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_comments (
  tenant          uuid,
  subject_type    text,
  subject_id      text,
  after           timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows        integer                  DEFAULT 100,
  skip            integer                  DEFAULT 0,
  after_id        uuid                     DEFAULT NULL::uuid,
  include_deleted boolean                  DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv uuid := "better_supabase"."comment_conversation"(list_comments.tenant, list_comments.subject_type, list_comments.subject_id);
begin
  if v_conv is null then
    return '[]'::jsonb;
  end if;
  perform "better_supabase"."record_subject_read"(list_comments.subject_type, list_comments.subject_id, null, 'comments', 'list_comments');
  return "better_supabase"."comments_json"(array(
    select x."id" from "better_supabase"."messages" x
    where x."conversation_id" = v_conv and x."sent_at" is not null
      and (coalesce(list_comments.include_deleted, true) or x."archived_at" is null)
      and (list_comments.after is null
        or (x."sent_at", x."id") > (list_comments.after, coalesce(list_comments.after_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_comments.max_rows, 100), 1), 500)
    offset greatest(coalesce(list_comments.skip, 0), 0)
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_conversations (
  tenant   uuid,
  kinds    text[]  DEFAULT NULL::text[],
  max_rows integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(
    to_jsonb(c) || jsonb_build_object(
      'unread', u.unread,
      'mentions', u.mentions,
      'lastReadAt', k."last_read_at",
      'notify', k."notify"
    ) order by c."last_message_at" desc nulls last, c."id"), '[]'::jsonb)
  from (
    select c.* from "better_supabase"."conversations" c
    join "better_supabase"."conversation_members" k on k."conversation_id" = c."id" and k."user_id" = auth.uid()
    where c."tenant_id" = list_conversations.tenant
      and (list_conversations.kinds is null and c."kind" <> 'inbox' or c."kind" = any (list_conversations.kinds))
    order by c."last_message_at" desc nulls last, c."id"
    limit least(greatest(coalesce(list_conversations.max_rows, 100), 1), 500)
  ) c
  join "better_supabase"."conversation_members" k on k."conversation_id" = c."id" and k."user_id" = auth.uid()
  cross join lateral (
    select count(*) as unread,
      count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) as mentions
    from "better_supabase"."messages" m
    where m."conversation_id" = c."id"
      and (m."thread_id" is null or m."broadcast")
      and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz)
      and m."archived_at" is null
      and m."author_id" is distinct from auth.uid()
  ) u
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_file_anchors (
  attachment uuid,
  max_rows   integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select "better_supabase"."messaging_messages_json"(array(
    select m."id" from "better_supabase"."messages" m
    where m."anchor" ->> 'kind' = 'file'
      and m."anchor" ->> 'attachmentId' = list_file_anchors.attachment::text
      and m."sent_at" is not null and m."archived_at" is null
    order by m."sent_at", m."id"
    limit least(greatest(coalesce(list_file_anchors.max_rows, 100), 1), 500)
  ))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_file_comments (
  attachment uuid,
  max_rows   integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return "better_supabase"."comments_json"(array(
    select x."id" from "better_supabase"."messages" x
    join "better_supabase"."conversations" c on c."id" = x."conversation_id" and c."kind" = 'subject'
    where x."anchor" ->> 'kind' = 'file'
      and x."anchor" ->> 'attachmentId' = list_file_comments.attachment::text
      and x."sent_at" is not null and x."archived_at" is null
    order by x."sent_at", x."id"
    limit least(greatest(coalesce(list_file_comments.max_rows, 100), 1), 500)
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_messages (
  conversation uuid,
  after        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  after_id     uuid                     DEFAULT NULL::uuid,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before_id    uuid                     DEFAULT NULL::uuid,
  max_rows     integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select "better_supabase"."messaging_messages_json"(array(
    select p."id" from (
      select m."id" from "better_supabase"."messages" m
      where m."conversation_id" = list_messages.conversation
        and (m."thread_id" is null or m."broadcast")
        and m."sent_at" is not null
        and (list_messages.after is null
          or (m."sent_at", m."id") > (list_messages.after, coalesce(list_messages.after_id, '00000000-0000-0000-0000-000000000000'::uuid)))
        and (list_messages.before is null
          or (m."sent_at", m."id") < (list_messages.before, coalesce(list_messages.before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
      order by
        case when list_messages.after is null then m."sent_at" end desc,
        case when list_messages.after is null then m."id" end desc,
        m."sent_at", m."id"
      limit least(greatest(coalesce(list_messages.max_rows, 50), 1), 200)
    ) p
    union all
    select m."id" from "better_supabase"."messages" m
    where m."conversation_id" = list_messages.conversation
      and m."sent_at" is null and m."archived_at" is null
      and m."author_id" = auth.uid()
      and list_messages.after is null and list_messages.before is null
  ))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_create (
  tenant           uuid,
  path             text,
  content          text,
  ns               jsonb   DEFAULT '{}'::jsonb,
  expected_version integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_create.ns ->> 'scope', 'user');
  v_agent := (memory_create.ns ->> 'agent_id')::uuid;
  v_chat := (memory_create.ns ->> 'chat_id')::uuid;
  v_project := (memory_create.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_create.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_create.ns ->> 'subject_id', '');
  v_private := coalesce((memory_create.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_create.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_create.tenant, 'memory.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_create.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_owner is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_create.tenant, 'memory.manage'), false)) then
    raise exception 'only admins change organization and record memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_create.path is null or length(memory_create.path) > 500 or memory_create.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_create.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_create.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if length(memory_create.content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_create.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null and x."path" = memory_create.path
  for update;
  if found then
    if memory_create.expected_version is not null and memory_create.expected_version <> v_row."version" then
      raise exception '% changed since version %', memory_create.path, memory_create.expected_version using errcode = '40001', hint = 'MEMORY_CONFLICT';
    end if;
    update "better_supabase"."memories" x set "content" = memory_create.content, "version" = x."version" + 1, "embedding" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  else
    if coalesce(memory_create.expected_version, 0) <> 0 then
      raise exception '% not found', memory_create.path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
    end if;
    insert into "better_supabase"."memories" ("organization_id", "owner_id", "scope", "agent_id", "chat_id", "project_id", "subject_type", "subject_id", "kind", "path", "content")
    values (memory_create.tenant, v_owner, v_scope, v_agent, v_chat, v_project, v_subject_type, v_subject_id, 'core', memory_create.path, memory_create.content)
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'category', v_row."category", 'confidence', v_row."confidence", 'expires_at', v_row."expires_at", 'use_count', v_row."use_count", 'last_used_at', v_row."last_used_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_delete (
  tenant uuid,
  path   text,
  ns     jsonb DEFAULT '{}'::jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_delete.ns ->> 'scope', 'user');
  v_agent := (memory_delete.ns ->> 'agent_id')::uuid;
  v_chat := (memory_delete.ns ->> 'chat_id')::uuid;
  v_project := (memory_delete.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_delete.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_delete.ns ->> 'subject_id', '');
  v_private := coalesce((memory_delete.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_delete.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_delete.tenant, 'memory.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_delete.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_owner is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_delete.tenant, 'memory.manage'), false)) then
    raise exception 'only admins change organization and record memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_delete.path is null or length(memory_delete.path) > 500 or memory_delete.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_delete.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_delete.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  update "better_supabase"."memories" x set "archived_at" = now(), "updated_at" = now()
  where x."organization_id" = memory_delete.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
    and (x."path" = memory_delete.path or x."path" like replace(replace(memory_delete.path, '_', '\_'), '%', '\%') || '/%');
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_forget (
  memory_id     uuid,
  superseded_by uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."memories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."memories" x where x."id" = memory_forget.memory_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or (v_row."owner_id" is null and coalesce(better_supabase.can('tenant', v_row."organization_id", 'memory.manage'), false))) then
    return false;
  end if;
  if memory_forget.superseded_by is null then
    update "better_supabase"."memories" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now() where x."id" = v_row."id";
  else
    update "better_supabase"."memories" x set "superseded_by" = memory_forget.superseded_by, "updated_at" = now() where x."id" = v_row."id";
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_insert (
  tenant      uuid,
  path        text,
  insert_line integer,
  insert_text text,
  ns          jsonb   DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
  v_lines text[];
  v_content text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_insert.ns ->> 'scope', 'user');
  v_agent := (memory_insert.ns ->> 'agent_id')::uuid;
  v_chat := (memory_insert.ns ->> 'chat_id')::uuid;
  v_project := (memory_insert.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_insert.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_insert.ns ->> 'subject_id', '');
  v_private := coalesce((memory_insert.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_insert.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_insert.tenant, 'memory.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_insert.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_owner is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_insert.tenant, 'memory.manage'), false)) then
    raise exception 'only admins change organization and record memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_insert.path is null or length(memory_insert.path) > 500 or memory_insert.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_insert.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_insert.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_insert.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null and x."path" = memory_insert.path
  for update;
  if not found then
    raise exception '% not found', memory_insert.path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  v_lines := case when v_row."content" = '' then '{}'::text[] else string_to_array(v_row."content", E'\n') end;
  if memory_insert.insert_line < 0 or memory_insert.insert_line > coalesce(array_length(v_lines, 1), 0) then
    raise exception 'line % is outside the file', memory_insert.insert_line using errcode = '22023', hint = 'MEMORY_LINE';
  end if;
  v_content := array_to_string(v_lines[1:memory_insert.insert_line] || string_to_array(coalesce(memory_insert.insert_text, ''), E'\n') || v_lines[memory_insert.insert_line + 1:], E'\n');
  if length(v_content) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  update "better_supabase"."memories" x set "content" = v_content, "version" = x."version" + 1, "embedding" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'category', v_row."category", 'confidence', v_row."confidence", 'expires_at', v_row."expires_at", 'use_count', v_row."use_count", 'last_used_at', v_row."last_used_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_list (
  tenant   uuid,
  ns       jsonb   DEFAULT '{}'::jsonb,
  kind     text    DEFAULT 'core'::text,
  max_rows integer DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_rows jsonb;
begin
  v_scope := coalesce(memory_list.ns ->> 'scope', 'user');
  v_agent := (memory_list.ns ->> 'agent_id')::uuid;
  v_chat := (memory_list.ns ->> 'chat_id')::uuid;
  v_project := (memory_list.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_list.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_list.ns ->> 'subject_id', '');
  v_private := coalesce((memory_list.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_list.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_list.tenant, 'memory.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_list.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'scope', x."scope", 'agent_id', x."agent_id", 'chat_id', x."chat_id", 'project_id', x."project_id", 'kind', x."kind", 'path', x."path", 'content', x."content", 'version', x."version", 'embedding_model', x."embedding_model", 'source_message_id', x."source_message_id", 'subject_type', x."subject_type", 'subject_id', x."subject_id", 'category', x."category", 'confidence', x."confidence", 'expires_at', x."expires_at", 'use_count', x."use_count", 'last_used_at', x."last_used_at", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."path", x."created_at" desc), '[]') into v_rows
  from (
    select * from "better_supabase"."memories" y
    where y."organization_id" = memory_list.tenant and y."owner_id" is not distinct from v_owner and y."scope" = v_scope and y."agent_id" is not distinct from v_agent and y."chat_id" is not distinct from v_chat and y."project_id" is not distinct from v_project and y."subject_type" is not distinct from v_subject_type and y."subject_id" is not distinct from v_subject_id and y."superseded_by" is null and y."archived_at" is null and (y."expires_at" is null or y."expires_at" > now()) and y."kind" = memory_list.kind
    order by y."path", y."created_at" desc
    limit least(greatest(memory_list.max_rows, 1), 1000)
  ) x;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_rename (
  tenant   uuid,
  old_path text,
  new_path text,
  ns       jsonb DEFAULT '{}'::jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_count integer;
  v_prefix text := replace(replace(memory_rename.old_path, '_', '\_'), '%', '\%') || '/%';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_rename.ns ->> 'scope', 'user');
  v_agent := (memory_rename.ns ->> 'agent_id')::uuid;
  v_chat := (memory_rename.ns ->> 'chat_id')::uuid;
  v_project := (memory_rename.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_rename.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_rename.ns ->> 'subject_id', '');
  v_private := coalesce((memory_rename.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_rename.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_rename.tenant, 'memory.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_rename.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_owner is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_rename.tenant, 'memory.manage'), false)) then
    raise exception 'only admins change organization and record memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_rename.old_path is null or length(memory_rename.old_path) > 500 or memory_rename.old_path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_rename.old_path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_rename.old_path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if memory_rename.new_path is null or length(memory_rename.new_path) > 500 or memory_rename.new_path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_rename.new_path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_rename.new_path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if memory_rename.new_path = memory_rename.old_path or memory_rename.new_path like v_prefix then
    raise exception 'cannot move % into itself', memory_rename.old_path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  if exists (
    select 1 from "better_supabase"."memories" x
    where x."organization_id" = memory_rename.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
      and (x."path" = memory_rename.new_path or x."path" like replace(replace(memory_rename.new_path, '_', '\_'), '%', '\%') || '/%')
  ) then
    raise exception '% already exists', memory_rename.new_path using errcode = '23505', hint = 'MEMORY_EXISTS';
  end if;
  update "better_supabase"."memories" x set
    "path" = memory_rename.new_path || substr(x."path", length(memory_rename.old_path) + 1),
    "version" = x."version" + 1, "updated_at" = now()
  where x."organization_id" = memory_rename.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null
    and (x."path" = memory_rename.old_path or x."path" like v_prefix);
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception '% not found', memory_rename.old_path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_restore (
  memory_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."memories"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."memories" x where x."id" = memory_restore.memory_id and x."archived_at" is not null;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."owner_id" = auth.uid(), false) or (v_row."owner_id" is null and coalesce(better_supabase.can('tenant', v_row."organization_id", 'memory.manage'), false))) then
    return false;
  end if;
  update "better_supabase"."memories" x set "archived_at" = null, "updated_at" = now() where x."id" = v_row."id";
  return true;
exception when unique_violation then
  raise exception '% already exists', v_row."path" using errcode = '23505', hint = 'MEMORY_EXISTS';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_search (
  tenant          uuid,
  query_embedding extensions.vector DEFAULT NULL::extensions.vector,
  query_text      text              DEFAULT NULL::text,
  ns              jsonb             DEFAULT '{}'::jsonb,
  k               integer           DEFAULT 8
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_rows jsonb;
  v_candidates integer := least(greatest(memory_search.k, 1) * 4, 400);
  v_scan text := current_setting('hnsw.iterative_scan', true);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_search.ns ->> 'scope', 'user');
  v_agent := (memory_search.ns ->> 'agent_id')::uuid;
  v_chat := (memory_search.ns ->> 'chat_id')::uuid;
  v_project := (memory_search.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_search.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_search.ns ->> 'subject_id', '');
  v_private := coalesce((memory_search.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_search.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_search.tenant, 'memory.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_search.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  perform set_config('hnsw.iterative_scan', 'relaxed_order', true);
  with scoped as materialized (
    select x."id" as id from "better_supabase"."memories" x
    where x."organization_id" = memory_search.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null and (x."expires_at" is null or x."expires_at" > now()) and x."kind" = 'archival'
  ),
  vector_hits as materialized (
    select t."id" as id, t."embedding" operator(extensions.<=>) memory_search.query_embedding as distance
    from "better_supabase"."memories" t
    where memory_search.query_embedding is not null and t."embedding" is not null and t."id" in (select scoped.id from scoped)
    order by t."embedding" operator(extensions.<=>) memory_search.query_embedding
    limit v_candidates
  ),
  vector_ranked as (
    select h.id, h.distance, row_number() over (order by h.distance) as rank from vector_hits h
  ),
  text_ranked as (
    select t."id" as id, row_number() over (order by ts_rank_cd(t."tsv", q) desc) as rank
    from "better_supabase"."memories" t, websearch_to_tsquery('simple'::regconfig, memory_search.query_text) q
    where memory_search.query_text is not null and t."tsv" @@ q and t."id" in (select scoped.id from scoped)
    limit v_candidates
  ),
  fused as materialized (
    select r.id, r.distance, r.score * coalesce(t."confidence", 1) as score
    from (
      select coalesce(v.id, x.id) as id, v.distance,
        coalesce(1.0 / (60 + v.rank), 0) + coalesce(1.0 / (60 + x.rank), 0) as score
      from vector_ranked v full join text_ranked x on x.id = v.id
    ) r join "better_supabase"."memories" t on t."id" = r.id
    order by score desc
    limit least(greatest(memory_search.k, 1), 100)
  ),
  used as (
    update "better_supabase"."memories" t set "use_count" = t."use_count" + 1, "last_used_at" = now()
    from fused f where t."id" = f.id
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'organization_id', t."organization_id", 'owner_id', t."owner_id", 'scope', t."scope", 'agent_id', t."agent_id", 'chat_id', t."chat_id", 'project_id', t."project_id", 'kind', t."kind", 'path', t."path", 'content', t."content", 'version', t."version", 'embedding_model', t."embedding_model", 'source_message_id', t."source_message_id", 'subject_type', t."subject_type", 'subject_id', t."subject_id", 'category', t."category", 'confidence', t."confidence", 'expires_at', t."expires_at", 'use_count', t."use_count", 'last_used_at', t."last_used_at", 'created_at', t."created_at", 'updated_at', t."updated_at") || jsonb_build_object('score', f.score, 'similarity', 1 - f.distance) order by f.score desc), '[]')
  into v_rows
  from fused f join "better_supabase"."memories" t on t."id" = f.id;
  perform set_config('hnsw.iterative_scan', coalesce(nullif(v_scan, ''), 'off'), true);
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_str_replace (
  tenant   uuid,
  path     text,
  old_text text,
  new_text text,
  ns       jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
  v_matches integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_scope := coalesce(memory_str_replace.ns ->> 'scope', 'user');
  v_agent := (memory_str_replace.ns ->> 'agent_id')::uuid;
  v_chat := (memory_str_replace.ns ->> 'chat_id')::uuid;
  v_project := (memory_str_replace.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_str_replace.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_str_replace.ns ->> 'subject_id', '');
  v_private := coalesce((memory_str_replace.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_str_replace.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_str_replace.tenant, 'memory.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_str_replace.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if v_owner is null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', memory_str_replace.tenant, 'memory.manage'), false)) then
    raise exception 'only admins change organization and record memory' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if memory_str_replace.path is null or length(memory_str_replace.path) > 500 or memory_str_replace.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_str_replace.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_str_replace.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_str_replace.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null and x."path" = memory_str_replace.path
  for update;
  if not found then
    raise exception '% not found', memory_str_replace.path using errcode = 'P0002', hint = 'MEMORY_NOT_FOUND';
  end if;
  if coalesce(length(memory_str_replace.old_text), 0) = 0 then
    raise exception 'old_text is empty' using errcode = '22023', hint = 'MEMORY_NO_MATCH';
  end if;
  v_matches := (length(v_row."content") - length(replace(v_row."content", memory_str_replace.old_text, ''))) / length(memory_str_replace.old_text);
  if v_matches = 0 then
    raise exception 'old_text does not appear in %', memory_str_replace.path using errcode = '22023', hint = 'MEMORY_NO_MATCH';
  elsif v_matches > 1 then
    raise exception 'old_text appears % times in %', v_matches, memory_str_replace.path using errcode = '22023', hint = 'MEMORY_AMBIGUOUS';
  end if;
  if length(replace(v_row."content", memory_str_replace.old_text, coalesce(memory_str_replace.new_text, ''))) > 100000 then
    raise exception 'memory content is limited to % characters', 100000 using errcode = '22023', hint = 'MEMORY_TOO_LARGE';
  end if;
  update "better_supabase"."memories" x set
    "content" = replace(x."content", memory_str_replace.old_text, coalesce(memory_str_replace.new_text, '')),
    "version" = x."version" + 1, "embedding" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'scope', v_row."scope", 'agent_id', v_row."agent_id", 'chat_id', v_row."chat_id", 'project_id', v_row."project_id", 'kind', v_row."kind", 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'embedding_model', v_row."embedding_model", 'source_message_id', v_row."source_message_id", 'subject_type', v_row."subject_type", 'subject_id', v_row."subject_id", 'category', v_row."category", 'confidence', v_row."confidence", 'expires_at', v_row."expires_at", 'use_count', v_row."use_count", 'last_used_at', v_row."last_used_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.memory_view (
  tenant uuid,
  path   text  DEFAULT '/memories'::text,
  ns     jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_scope text;
  v_agent uuid;
  v_chat uuid;
  v_project uuid;
  v_subject_type text;
  v_subject_id text;
  v_private boolean;
  v_owner uuid;
  v_row "better_supabase"."memories"%rowtype;
  v_entries jsonb;
begin
  v_scope := coalesce(memory_view.ns ->> 'scope', 'user');
  v_agent := (memory_view.ns ->> 'agent_id')::uuid;
  v_chat := (memory_view.ns ->> 'chat_id')::uuid;
  v_project := (memory_view.ns ->> 'project_id')::uuid;
  v_subject_type := nullif(memory_view.ns ->> 'subject_type', '');
  v_subject_id := nullif(memory_view.ns ->> 'subject_id', '');
  v_private := coalesce((memory_view.ns ->> 'private')::boolean, false);
  v_owner := case when v_scope in ('organization', 'record') and not v_private then null when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then (memory_view.ns ->> 'owner_id')::uuid else auth.uid() end;
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (auth.uid() is null or not coalesce(better_supabase.can('tenant', memory_view.tenant, 'memory.read'), false)) then
    raise exception 'you may not use memory here' using errcode = '42501', hint = 'MEMORY_FORBIDDEN';
  end if;
  if v_scope not in ('user', 'agent', 'chat', 'project', 'organization', 'record')
    or (v_scope = 'agent') <> (v_agent is not null)
    or (v_scope = 'chat') <> (v_chat is not null)
    or (v_scope = 'project') <> (v_project is not null)
    or (v_scope = 'record') <> (v_subject_id is not null)
    or (v_subject_id is not null) <> (v_subject_type is not null)
    or (v_owner is null and (v_scope not in ('organization', 'record') or v_private)) then
    raise exception 'ns % is not a memory namespace', memory_view.ns using errcode = '22023', hint = 'MEMORY_NAMESPACE';
  end if;
  if memory_view.path is null or length(memory_view.path) > 500 or memory_view.path !~ '^/memories(/[A-Za-z0-9._ -]+)*$' or memory_view.path ~ '(^|/)[.]{1,2}(/|$)' then
    raise exception '% is not a path under /memories', memory_view.path using errcode = '22023', hint = 'MEMORY_PATH';
  end if;
  select * into v_row from "better_supabase"."memories" x
  where x."organization_id" = memory_view.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null and x."path" = memory_view.path;
  if found then
    return jsonb_build_object('type', 'file', 'path', v_row."path", 'content', v_row."content", 'version', v_row."version", 'updated_at', v_row."updated_at");
  end if;
  select jsonb_agg(jsonb_build_object('path', x."path", 'size', length(x."content"), 'updated_at', x."updated_at") order by x."path")
  into v_entries
  from "better_supabase"."memories" x
  where x."organization_id" = memory_view.tenant and x."owner_id" is not distinct from v_owner and x."scope" = v_scope and x."agent_id" is not distinct from v_agent and x."chat_id" is not distinct from v_chat and x."project_id" is not distinct from v_project and x."subject_type" is not distinct from v_subject_type and x."subject_id" is not distinct from v_subject_id and x."superseded_by" is null and x."archived_at" is null and x."path" like replace(replace(memory_view.path, '_', '\_'), '%', '\%') || '/%';
  if v_entries is null and memory_view.path <> '/memories' then
    return null;
  end if;
  return jsonb_build_object('type', 'directory', 'path', memory_view.path, 'entries', coalesce(v_entries, '[]'));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.messaging_message_broadcast()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null and new."sent_at" is not null then
    perform realtime.send(
      jsonb_build_object('conversationId', new."conversation_id", 'messageId', new."id", 'threadId', new."thread_id"),
      case when tg_op = 'INSERT' or old."sent_at" is null then 'message' when new."archived_at" is not null then 'message_deleted' else 'message_updated' end,
      'messages:' || new."conversation_id"::text,
      true
    );
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.messaging_message_written()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."sent_at" is null then
    return null;
  end if;
  if tg_op = 'INSERT' or old."sent_at" is null then
    update "better_supabase"."conversations" c set "last_message_at" = greatest(coalesce(c."last_message_at", new."sent_at"), new."sent_at"), "updated_at" = now()
    where c."id" = new."conversation_id";
  end if;
  if new."thread_id" is not null and (tg_op = 'INSERT' or old."sent_at" is null or new."archived_at" is distinct from old."archived_at") then
    update "better_supabase"."messages" r set
      "reply_count" = (select count(*) from "better_supabase"."messages" x where x."thread_id" = r."id" and x."sent_at" is not null and x."archived_at" is null),
      "last_reply_at" = (select max(x."sent_at") from "better_supabase"."messages" x where x."thread_id" = r."id" and x."archived_at" is null),
      "reply_user_ids" = array(
        select y.u from (
          select x."author_id" as u, min(x."sent_at") as first
          from "better_supabase"."messages" x
          where x."thread_id" = r."id" and x."sent_at" is not null and x."archived_at" is null and x."author_id" is not null
          group by x."author_id"
        ) y order by y.first limit 3
      )
    where r."id" = new."thread_id";
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.moderation_apply (
  item_id   uuid,
  action    text,
  reason    text    DEFAULT NULL::text,
  automatic boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."moderation_items";
  v_row "better_supabase"."moderation_items";
  v_ban "better_supabase"."moderation_bans";
  v_status text;
begin
  select * into v_old from "better_supabase"."moderation_items" x where x."id" = moderation_apply.item_id for update;
  if v_old."id" is null then
    raise exception 'moderation item not found' using errcode = 'P0002', hint = 'MODERATION_ITEM_NOT_FOUND';
  end if;
  v_status := case moderation_apply.action
    when 'approve' then 'visible'
    when 'restore' then 'visible'
    when 'hide' then 'hidden'
    when 'auto_hide' then 'hidden'
    when 'remove' then 'removed'
    when 'ban' then 'removed'
  end;
  if v_status is null then
    raise exception 'action must be approve, hide, remove, restore or ban' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if length(moderation_apply.reason) > 1000 then
    raise exception 'reason must be at most 1000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if moderation_apply.action = 'restore' and v_old."status" not in ('hidden', 'removed') then
    raise exception 'only hidden or removed content can be restored' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if moderation_apply.action = 'ban' and v_old."author_id" is null then
    raise exception 'this content has no author to ban' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if moderation_apply.action = 'restore' and v_old."status" = 'removed' and v_old."subject_type" = 'message' then
    raise exception 'a removed message can''t be restored' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  update "better_supabase"."moderation_items" x
  set "status" = v_status,
    "reason" = case when v_status = 'visible' then null else nullif(trim(moderation_apply.reason), '') end,
    "decided_by" = case when moderation_apply.automatic then null else auth.uid() end,
    "decided_at" = now(),
    "open_reports" = case when moderation_apply.action = 'auto_hide' then x."open_reports" else 0 end,
    "updated_at" = now()
  where x."id" = v_old."id"
  returning * into v_row;
  if moderation_apply.action <> 'auto_hide' then
    update "better_supabase"."moderation_reports" x
    set "status" = case when v_status = 'visible' then 'dismissed' else 'resolved' end,
      "resolved_by" = auth.uid(), "resolved_at" = now()
    where x."item_id" = v_row."id" and x."status" = 'open';
  end if;
  insert into "better_supabase"."moderation_actions" ("tenant_id", "item_id", "action", "from_status", "to_status", "reason", "actor_id")
  values (v_row."tenant_id", v_row."id", moderation_apply.action, v_old."status", v_status, nullif(trim(moderation_apply.reason), ''),
    case when moderation_apply.automatic then null else auth.uid() end);
  if v_row."subject_type" = 'message' and v_status = 'removed' then
    update "better_supabase"."messages" x
    set "body" = '', "document" = null, "mentions" = '{}', "mention_scope" = null,
      "pinned_at" = null, "pinned_by" = null, "archived_at" = now()
    where x."id"::text = v_row."subject_id" and x."archived_at" is null;
  end if;
  if moderation_apply.action = 'ban' and not "better_supabase"."moderation_banned"(v_row."tenant_id", v_row."author_id") then
    delete from "better_supabase"."moderation_bans" x where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."author_id" and x."lifted_at" is null;
    insert into "better_supabase"."moderation_bans" ("tenant_id", "user_id", "reason", "banned_by")
    values (v_row."tenant_id", v_row."author_id", nullif(trim(moderation_apply.reason), ''), auth.uid())
    returning * into v_ban;
    perform "better_supabase".emit_event('moderation_ban.created', jsonb_build_object('organizationId', v_ban."tenant_id", 'id', v_ban."id", 'userId', v_ban."user_id", 'expiresAt', v_ban."expires_at"), 'moderation-bans/' || v_ban."id"::text, (v_ban."tenant_id")::text, null, 'better-supabase/moderation');
  perform better_supabase.audit_event(
    event_type => 'moderation_ban.created',
    category => 'security',
    target_type => 'user',
    record_id => v_ban."user_id"::text,
    summary => 'banned a user',
    tenant => (v_ban."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_ban."tenant_id", 'id', v_ban."id", 'userId', v_ban."user_id", 'expiresAt', v_ban."expires_at")
  );
  end if;
  perform "better_supabase".emit_event('moderation_item.decided', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'action', moderation_apply.action, 'status', v_status, 'previousStatus', v_old."status", 'automatic', moderation_apply.automatic), 'moderation-items/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/moderation');
  perform better_supabase.audit_event(
    event_type => 'moderation_item.decided',
    category => 'data',
    target_type => 'moderation_item',
    record_id => v_row."id"::text,
    target_label => v_row."subject_type" || '/' || v_row."subject_id",
    summary => 'moderation: ' || moderation_apply.action,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'action', moderation_apply.action, 'status', v_status, 'previousStatus', v_old."status", 'automatic', moderation_apply.automatic)
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'authorId', v_row."author_id", 'status', v_row."status", 'openReports', v_row."open_reports", 'reason', v_row."reason", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
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
      and m."archived_at" is null
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

CREATE OR REPLACE FUNCTION better_supabase.notify_due_drive_reviews()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_count integer := 0;
  v_claims text;
begin
  for v_node in
    select * from "better_supabase"."drive_nodes" x
    where x."document_status" = 'effective' and x."next_review_on" <= current_date
      and x."review_notified_for" is distinct from x."next_review_on" and x."archived_at" is null
    for update skip locked
  loop
    perform "better_supabase".emit_event('drive_node.review_requested', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'ownerId', v_node."document_owner_id", 'nextReviewOn', v_node."next_review_on"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
    if v_node."document_owner_id" is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'drive.document_review_due',
        'tenant', v_node."tenant_id",
        'actor', null,
        'subject_type', 'drive_node',
        'subject_id', v_node."id"::text,
        'summary', v_node."document_number" || ' ' || v_node."name",
        'recipients', to_jsonb(array[v_node."document_owner_id"]),
        'key', 'drive.document_review_due:' || v_node."id"::text || ':' || v_node."next_review_on"::text,
        'data', jsonb_build_object('nodeId', v_node."id", 'documentNumber', v_node."document_number", 'nextReviewOn', v_node."next_review_on")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    update "better_supabase"."drive_nodes" x set "review_notified_for" = v_node."next_review_on" where x."id" = v_node."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pending_memory_embeddings (
  batch integer DEFAULT 64
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'content', x."content", 'hash', md5(x."content"))), '[]')
  from (
    select * from "better_supabase"."memories" y where y."embedding" is null and y."superseded_by" is null and y."archived_at" is null and (y."expires_at" is null or y."expires_at" > now())
    order by y."updated_at"
    limit least(greatest(pending_memory_embeddings.batch, 1), 2048)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pin_message (
  message uuid,
  pinned  boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = pin_message.message and m."archived_at" is null and m."sent_at" is not null;
  if not found or not "better_supabase"."can_conversation"(v_msg."conversation_id", 'send') then
    raise exception 'no such message you can pin' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  update "better_supabase"."messages" m
  set "pinned_at" = case when pin_message.pinned then coalesce(m."pinned_at", now()) end,
    "pinned_by" = case when pin_message.pinned then coalesce(m."pinned_by", auth.uid()) end
  where m."id" = v_msg."id"
  returning * into v_msg;
  perform "better_supabase".emit_event('message.pinned', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text, 'pinned', pin_message.pinned)
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  return "better_supabase"."messaging_messages_json"(array[v_msg."id"]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.posts_replied()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update "better_supabase"."posts" x set
    "reply_count" = (
      select count(*) from "better_supabase"."messages" m
      where m."conversation_id" = new."conversation_id"
        and m."sent_at" is not null and m."archived_at" is null
    ),
    "last_activity_at" = greatest(x."last_activity_at", coalesce(new."sent_at", x."last_activity_at"))
  from "better_supabase"."conversations" c
  where c."id" = new."conversation_id" and c."subject_type" = 'post'
    and x."id"::text = c."subject_id" and x."tenant_id" = c."tenant_id";
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_due_messages (
  max_rows integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_sent integer := 0;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'publish_due_messages runs as the service role' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  for v_id in
    select m."id" from "better_supabase"."messages" m
    where m."sent_at" is null and m."archived_at" is null and m."scheduled_at" <= now()
    order by m."scheduled_at", m."id"
    limit least(greatest(coalesce(publish_due_messages.max_rows, 100), 1), 1000)
    for update skip locked
  loop
    update "better_supabase"."messages" m set "sent_at" = now() where m."id" = v_id;
    perform "better_supabase"."messaging_message_sent"(v_id);
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_memories (
  retention_days integer DEFAULT 30,
  batch          integer DEFAULT 1000,
  tenant         uuid    DEFAULT NULL::uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  delete from "better_supabase"."memories" x
  where x."id" in (
    select y."id" from "better_supabase"."memories" y
    where (purge_memories.tenant is null or y."organization_id" = purge_memories.tenant)
      and (y."archived_at" < now() - make_interval(days => greatest(purge_memories.retention_days, 0)) or y."expires_at" < now())
    limit least(greatest(purge_memories.batch, 1), 10000)
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.react_to_inbox_message (
  message uuid,
  emoji   text,
  present boolean DEFAULT true,
  actor   text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages"%rowtype;
  v_conversation uuid;
  v_who text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select m.* into v_msg from "better_supabase"."messages" m
  join "better_supabase"."inbox_message_details" d on d."message_id" = m."id"
  where m."id" = react_to_inbox_message.message and m."archived_at" is null;
  if not found then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  v_conversation := v_msg."conversation_id";
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_who := coalesce(react_to_inbox_message.actor, 'bot');
  elsif v_msg."kind" = 'message' and "better_supabase"."inbox_conversation_allowed"(v_conversation::text, true) then
    v_who := (select auth.uid())::text;
  elsif v_msg."kind" = 'note' and coalesce(better_supabase.can('tenant', v_msg."tenant_id", 'inbox.reply'), false) then
    v_who := (select auth.uid())::text;
  else
    raise exception 'not allowed to react to this message' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if length(react_to_inbox_message.emoji) not between 1 and 64 then
    raise exception 'emoji must be 1 to 64 characters' using errcode = '22023', hint = 'INBOX_REACTION_INVALID';
  end if;
  if coalesce(react_to_inbox_message.present, true) then
    insert into "better_supabase"."reactions" ("tenant_id", "subject_type", "subject_id", "actor", "user_id", "emoji")
    values (v_msg."tenant_id", 'message', v_msg."id"::text, v_who, case when v_who ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then v_who::uuid end, react_to_inbox_message.emoji)
    on conflict do nothing;
  else
    delete from "better_supabase"."reactions" x
    where x."subject_type" = 'message' and x."subject_id" = v_msg."id"::text
      and x."actor" = v_who and x."emoji" = react_to_inbox_message.emoji;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('conversationId', v_conversation, 'messageId', v_msg."id"),
      'message_updated',
      'messages:' || v_conversation::text,
      true
    );
  end if;
  return coalesce("better_supabase"."reaction_summary"(v_msg."tenant_id", 'message', array[v_msg."id"::text]) -> v_msg."id"::text, '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reaction_subject_visible (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return case reaction_subject_visible.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null and (coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."deleted_at" is null)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    else false
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_summary (
  subject_type text,
  subject_id   text,
  sections     text[],
  seen_at      timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_counts jsonb := '{}'::jsonb;
  v_unread jsonb := '{}'::jsonb;
  v_count bigint;
  v_latest timestamptz;
  v_seen timestamptz;
begin
  if coalesce(cardinality(record_summary.sections), 0) > 20 then
    raise exception 'record_summary takes at most 20 sections'
      using errcode = '22023', hint = 'RECORD_SECTIONS_TOO_MANY';
  end if;
  if not "better_supabase"."can_subject"(record_summary.subject_type, record_summary.subject_id, 'read') then
    return null;
  end if;
  perform "better_supabase"."record_subject_read"(record_summary.subject_type, record_summary.subject_id, null, 'subjects', 'record_summary');
  if 'comments' = any (record_summary.sections) then
    select count(*), max(x."sent_at")
      into v_count, v_latest
      from "better_supabase"."messages" x
      join "better_supabase"."conversations" c on c."id" = x."conversation_id"
        and c."kind" = 'subject'
      where c."subject_type"::text = record_summary.subject_type
        and c."subject_id"::text = record_summary.subject_id
        and x."sent_at" is not null and x."archived_at" is null;
    v_seen := coalesce((select "better_supabase"."conversation_read_at"(c."id") from "better_supabase"."conversations" c
        where c."kind" = 'subject'
          and c."subject_type" = record_summary.subject_type
          and c."subject_id" = record_summary.subject_id), record_summary.seen_at);
    v_counts := v_counts || jsonb_build_object('comments', v_count);
    v_unread := v_unread || jsonb_build_object('comments',
      v_seen is not null and v_latest is not null and v_latest > v_seen);
  end if;
  if 'attachments' = any (record_summary.sections) then
    select count(*), max(x."uploaded_at")
      into v_count, v_latest
      from "better_supabase"."attachments" x
      where x."subject_type"::text = record_summary.subject_type
        and x."subject_id"::text = record_summary.subject_id
        and x."uploaded_at" is not null and x."status" <> 'infected';
    v_seen := record_summary.seen_at;
    v_counts := v_counts || jsonb_build_object('attachments', v_count);
    v_unread := v_unread || jsonb_build_object('attachments',
      v_seen is not null and v_latest is not null and v_latest > v_seen);
  end if;
  return jsonb_build_object(
    'type', record_summary.subject_type,
    'id', record_summary.subject_id,
    'title', "better_supabase"."subject_title"(record_summary.subject_type, record_summary.subject_id),
    'url', "better_supabase"."subject_url"(record_summary.subject_type, record_summary.subject_id),
    'counts', v_counts,
    'unread', v_unread);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_team_tenant (
  subject_type text,
  subject_id   text
)
  RETURNS uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  case record_team_tenant.subject_type
    when 'customer' then
      select s."organization_id" into v_tenant from "public"."customers" s
      where s."id" = (record_team_tenant.subject_id)::uuid and s."archived_at" is null;
    when 'drive_node' then
      select s."tenant_id" into v_tenant from "better_supabase"."drive_nodes" s
      where s."id" = (record_team_tenant.subject_id)::uuid and s."archived_at" is null;
    else
      v_tenant := null;
  end case;
  return v_tenant;
exception
  when invalid_text_representation then
    return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.report_content (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  reason       text,
  note         text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_author uuid;
  v_item "better_supabase"."moderation_items";
  v_report "better_supabase"."moderation_reports";
  v_auto boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to report content' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if not coalesce(better_supabase.can('tenant', report_content.tenant, 'moderation.report'), false) then
    raise exception 'not allowed to report content' using errcode = '42501', hint = 'MODERATION_FORBIDDEN';
  end if;
  if "better_supabase"."moderation_banned"(report_content.tenant, v_me) then
    raise exception 'you are banned in this organization' using errcode = '42501', hint = 'MODERATION_BANNED';
  end if;
  if report_content.reason is null or report_content.reason not in ('spam', 'abuse', 'harassment', 'off_topic', 'illegal', 'other') then
    raise exception 'reason must be one of spam, abuse, harassment, off_topic, illegal, other' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if length(report_content.note) > 1000 then
    raise exception 'note must be at most 1000 characters' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if report_content.subject_type is null or report_content.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$'
    or report_content.subject_id is null or length(report_content.subject_id) not between 1 and 200 then
    raise exception 'a report needs a subject type and id' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  if report_content.subject_type = 'message' then
    select x."author_id" into v_author from "better_supabase"."messages" x
    where x."id"::text = report_content.subject_id and x."tenant_id" = report_content.tenant and x."archived_at" is null;
    if not found then
      raise exception 'there is no such message to report' using errcode = 'P0002', hint = 'MODERATION_SUBJECT_NOT_FOUND';
    end if;
  end if;
  insert into "better_supabase"."moderation_items" ("tenant_id", "subject_type", "subject_id", "author_id")
  values (report_content.tenant, report_content.subject_type, report_content.subject_id, v_author)
  on conflict ("tenant_id", "subject_type", "subject_id") do nothing;
  select * into v_item from "better_supabase"."moderation_items" x
  where x."tenant_id" = report_content.tenant and x."subject_type" = report_content.subject_type and x."subject_id" = report_content.subject_id
  for update;
  if v_item."author_id" = v_me then
    raise exception 'you can''t report your own content' using errcode = '22023', hint = 'MODERATION_INVALID';
  end if;
  insert into "better_supabase"."moderation_reports" ("tenant_id", "item_id", "reporter_id", "reason", "note")
  values (report_content.tenant, v_item."id", v_me, report_content.reason, nullif(trim(report_content.note), ''))
  on conflict ("item_id", "reporter_id") where "status" = 'open' do nothing
  returning * into v_report;
  if v_report."id" is null then
    select * into v_report from "better_supabase"."moderation_reports" x
    where x."item_id" = v_item."id" and x."reporter_id" = v_me and x."status" = 'open';
    return jsonb_build_object('id', v_report."id", 'organizationId', v_report."tenant_id", 'itemId', v_report."item_id", 'reporterId', v_report."reporter_id", 'reason', v_report."reason", 'note', v_report."note", 'status', v_report."status", 'resolvedBy', v_report."resolved_by", 'resolvedAt', v_report."resolved_at", 'createdAt', v_report."created_at") || jsonb_build_object('autoHidden', false);
  end if;
  update "better_supabase"."moderation_items" x
  set "open_reports" = (select count(*) from "better_supabase"."moderation_reports" y where y."item_id" = x."id" and y."status" = 'open'),
    "updated_at" = now()
  where x."id" = v_item."id"
  returning * into v_item;
  perform "better_supabase".emit_event('moderation_report.created', jsonb_build_object('organizationId', v_item."tenant_id", 'id', v_report."id", 'itemId', v_item."id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'reason', v_report."reason"), 'moderation-reports/' || v_report."id"::text, (v_item."tenant_id")::text, null, 'better-supabase/moderation');
  if v_item."status" = 'visible' and v_item."open_reports" >= 3 then
    perform "better_supabase"."moderation_apply"(v_item."id", 'auto_hide', 'Hidden after 3 reports', true);
    v_auto := true;
  end if;
  return jsonb_build_object('id', v_report."id", 'organizationId', v_report."tenant_id", 'itemId', v_report."item_id", 'reporterId', v_report."reporter_id", 'reason', v_report."reason", 'note', v_report."note", 'status', v_report."status", 'resolvedBy', v_report."resolved_by", 'resolvedAt', v_report."resolved_at", 'createdAt', v_report."created_at") || jsonb_build_object('autoHidden', v_auto);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_message (
  message  uuid,
  resolved boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = resolve_message.message and m."thread_id" is null and m."archived_at" is null and m."sent_at" is not null;
  if not found or not "better_supabase"."can_conversation"(v_msg."conversation_id", 'send') then
    raise exception 'no such thread you can resolve' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  update "better_supabase"."messages" m
  set "resolved_at" = case when resolve_message.resolved then coalesce(m."resolved_at", now()) end,
    "resolved_by" = case when resolve_message.resolved then coalesce(m."resolved_by", auth.uid()) end
  where m."id" = v_msg."id"
  returning * into v_msg;
  perform "better_supabase".emit_event('message.resolved', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text, 'resolved', resolve_message.resolved)
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  return "better_supabase"."messaging_messages_json"(array[v_msg."id"]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when 'message' then
      select s."tenant_id", s."body"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."messages" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'channel' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."topic"::text, s."purpose"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."channels" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'company' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."domain"::text), ''), '/crm/contacts/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."companies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'person' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."title"::text), ''), '/crm/contacts/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."people" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'deal' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."note"::text), ''), '/crm/deals'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."deals" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'course' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."courses" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'post' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."posts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'activity' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text, s."outcome"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."activities" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_item' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."body"::text), ''), '/work'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."work_items" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'employee' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."job_title"::text), ''), '/people'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."employees" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."slug"::text), ''), '/shop'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."products" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product_variant' then
      select s."tenant_id", s."sku"::text, nullif(concat_ws(E'\n', s."title"::text, s."barcode"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."product_variants" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'calendar_event' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."location"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."calendar_events" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'risk' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."cause"::text, s."consequence"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."risks" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'case' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."root_cause"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."cases" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."scope"::text, s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."inspections" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."location"::text, s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."meetings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'production_order' then
      select s."tenant_id", s."number"::text, nullif(concat_ws(E'\n', s."note"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."production_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'content_entry' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."content_entries" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'customer' then
      select s."organization_id", s."name"::text, null, '/customers/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "public"."customers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'drive_node' then
      select s."tenant_id", f."name"::text, nullif(concat_ws(E'\n', f."content"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."drive_nodes" s
        join "better_supabase"."drive_node_search" f on f."id"::text = s."id"::text
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'project' then
      select s."organization_id", s."name"::text, null, '/projects/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "public"."projects" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    else
      raise exception 'this subject type has no search entry in config.subjects' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now()
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "updated_at" = now();
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_message (
  conversation uuid,
  body         text,
  attrs        jsonb  DEFAULT '{}'::jsonb,
  attachments  uuid[] DEFAULT '{}'::uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations";
  v_id uuid;
  v_parent uuid := nullif(send_message.attrs ->> 'parentId', '')::uuid;
  v_root uuid;
  v_parsed jsonb := "better_supabase"."parse_mentions"(send_message.body);
  v_mentions uuid[];
  v_scheduled timestamptz := nullif(send_message.attrs ->> 'scheduledFor', '')::timestamptz;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = send_message.conversation;
  if not found or not "better_supabase"."can_conversation"(v_conv."id", 'read') then
    raise exception 'no such conversation you can read' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if v_conv."kind" = 'inbox' then
    raise exception 'write to an inbox conversation through send_inbox_message' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if v_conv."access" = 'tenant' and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and v_conv."archived_at" is null
    and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'messages.send'), false) then
    perform "better_supabase"."add_conversation_members"(v_conv."id", array[auth.uid()]);
  end if;
  if not "better_supabase"."can_conversation"(v_conv."id", 'send') then
    raise exception 'not allowed to send messages here' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if nullif(trim(coalesce(send_message.body, '')), '') is null and cardinality(coalesce(send_message.attachments, '{}')) = 0 then
    raise exception 'a message needs a body or a file' using errcode = '23502', hint = 'MESSAGING_BODY_REQUIRED';
  end if;
  if v_parent is not null then
    select m."thread_id" into v_root from "better_supabase"."messages" m
    where m."id" = v_parent and m."conversation_id" = v_conv."id"
      and m."sent_at" is not null and m."archived_at" is null;
    if not found then
      raise exception 'reply to a sent message in the same conversation' using errcode = '22023', hint = 'MESSAGING_PARENT_INVALID';
    end if;
    -- One level of threads: a reply to a reply joins the root's thread.
    v_parent := coalesce(v_root, v_parent);
  end if;
  if v_parent is null and send_message.attrs -> 'anchor' ->> 'kind' = 'file' then
    if not "better_supabase"."messaging_file_anchor_valid"(send_message.attrs -> 'anchor') then
      raise exception 'a file anchor needs an attachmentId, a page from 1, a region inside 0 to 1 and a time span from 0' using errcode = '22023', hint = 'MESSAGING_ANCHOR_INVALID';
    end if;
    if not exists (
      select 1 from "better_supabase"."attachments" a
      where a."id" = (send_message.attrs -> 'anchor' ->> 'attachmentId')::uuid
        and a."organization_id" = v_conv."tenant_id"
        and a."status" <> 'infected'
        and ((a."subject_type" = v_conv."subject_type" and a."subject_id" = v_conv."subject_id")
          or (a."subject_type" = 'message' and exists (
            select 1 from "better_supabase"."messages" m
            where m."id"::text = a."subject_id" and m."conversation_id" = v_conv."id")))
    ) then
      raise exception 'anchor the message to a file on this record or in this conversation' using errcode = '22023', hint = 'MESSAGING_ANCHOR_INVALID';
    end if;
  end if;
  if v_scheduled is not null and v_scheduled <= now() then
    v_scheduled := null;
  end if;
  v_mentions := array(
    select distinct x from (
      select (jsonb_array_elements_text(coalesce(send_message.attrs -> 'mentions', '[]'::jsonb)))::uuid as x
      union
      select (jsonb_array_elements_text(v_parsed -> 'users'))::uuid
    ) s
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_message_send"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using send_message.conversation, send_message.body, send_message.attrs;
    end if;
  end;
  begin
    insert into "better_supabase"."messages" ("tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "anchor",
      "mentions", "mention_scope", "broadcast", "scheduled_at", "sent_at")
    values (v_conv."tenant_id", v_conv."id", v_parent, case when v_parent is null then null else coalesce(v_root, v_parent) end,
      auth.uid(), coalesce(send_message.body, ''), send_message.attrs -> 'document',
      case when v_parent is null then send_message.attrs -> 'anchor' end, v_mentions,
      case when v_conv."access" = 'subject' then null else v_parsed ->> 'scope' end,
      v_parent is not null and coalesce((send_message.attrs ->> 'broadcast')::boolean, false),
      v_scheduled, case when v_scheduled is null then now() end)
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a message field has an invalid value' using errcode = '22023', hint = 'MESSAGING_MESSAGE_INVALID';
  end;
  -- Files the caller uploaded to the conversation move onto the message.
  if cardinality(coalesce(send_message.attachments, '{}')) > 0 then
    update "better_supabase"."attachments" a
    set "subject_type" = 'message', "subject_id" = v_id::text
    where a."id" = any (send_message.attachments)
      and a."organization_id" = v_conv."tenant_id"
      and a."subject_type" = 'conversation' and a."subject_id" = v_conv."id"::text
      and a."uploaded_by" = auth.uid()
      and a."status" <> 'infected';
    get diagnostics v_count = row_count;
    if v_count <> cardinality(array(select distinct x from unnest(send_message.attachments) x)) then
      raise exception 'attach files you uploaded to this conversation' using errcode = '22023', hint = 'MESSAGING_ATTACHMENT_INVALID';
    end if;
  end if;
  if v_scheduled is null then
    perform "better_supabase"."messaging_message_sent"(v_id);
  else
    perform "better_supabase"."enqueue_job"(queue => 'messaging', payload => jsonb_build_object('type', 'message.publish', 'messageId', v_id), delay => greatest(ceil(extract(epoch from (v_scheduled - now())))::integer, 0), dedupe_key => 'message.publish:' || v_id::text, dedupe_running => false);
    null;
  end if;
  return "better_supabase"."messaging_messages_json"(array[v_id]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_title (
  subject_type text,
  subject_id   text
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case subject_title.subject_type
    when 'message' then
      return (select s."body"::text from "better_supabase"."messages" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'conversation' then
      return (select s."title"::text from "better_supabase"."conversations" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'channel' then
      return (select s."name"::text from "better_supabase"."channels" s where s."id" = (subject_title.subject_id)::uuid);
    when 'company' then
      return (select s."name"::text from "better_supabase"."companies" s where s."id" = (subject_title.subject_id)::uuid);
    when 'person' then
      return (select s."name"::text from "better_supabase"."people" s where s."id" = (subject_title.subject_id)::uuid);
    when 'deal' then
      return (select s."name"::text from "better_supabase"."deals" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'course' then
      return (select s."title"::text from "better_supabase"."courses" s where s."id" = (subject_title.subject_id)::uuid);
    when 'post' then
      return (select s."title"::text from "better_supabase"."posts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'activity' then
      return (select s."title"::text from "better_supabase"."activities" s where s."id" = (subject_title.subject_id)::uuid);
    when 'quote' then
      return (select s."title"::text from "better_supabase"."quotes" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_item' then
      return (select s."title"::text from "better_supabase"."work_items" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'employee' then
      return (select s."name"::text from "better_supabase"."employees" s where s."id" = (subject_title.subject_id)::uuid);
    when 'invoice' then
      return (select s."title"::text from "better_supabase"."invoices" s where s."id" = (subject_title.subject_id)::uuid);
    when 'ledger_account' then
      return (select s."name"::text from "better_supabase"."ledger_accounts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product' then
      return (select s."title"::text from "better_supabase"."products" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product_variant' then
      return (select s."sku"::text from "better_supabase"."product_variants" s where s."id" = (subject_title.subject_id)::uuid);
    when 'rfq' then
      return (select s."title"::text from "better_supabase"."rfqs" s where s."id" = (subject_title.subject_id)::uuid);
    when 'till' then
      return (select s."name"::text from "better_supabase"."tills" s where s."id" = (subject_title.subject_id)::uuid);
    when 'order' then
      return (select s."number"::text from "better_supabase"."orders" s where s."id" = (subject_title.subject_id)::uuid);
    when 'calendar_event' then
      return (select s."title"::text from "better_supabase"."calendar_events" s where s."id" = (subject_title.subject_id)::uuid);
    when 'booking' then
      return (select s."customer_name"::text from "better_supabase"."bookings" s where s."id" = (subject_title.subject_id)::uuid);
    when 'asset' then
      return (select s."name"::text from "better_supabase"."assets" s where s."id" = (subject_title.subject_id)::uuid);
    when 'asset_location' then
      return (select s."name"::text from "better_supabase"."asset_locations" s where s."id" = (subject_title.subject_id)::uuid);
    when 'lease' then
      return (select s."title"::text from "better_supabase"."leases" s where s."id" = (subject_title.subject_id)::uuid);
    when 'expense_report' then
      return (select s."title"::text from "better_supabase"."expense_reports" s where s."id" = (subject_title.subject_id)::uuid);
    when 'expense_line' then
      return (select s."description"::text from "better_supabase"."expense_lines" s where s."id" = (subject_title.subject_id)::uuid);
    when 'donation_fund' then
      return (select s."name"::text from "better_supabase"."donation_funds" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_order' then
      return (select s."title"::text from "better_supabase"."work_orders" s where s."id" = (subject_title.subject_id)::uuid);
    when 'shipment' then
      return (select s."reference"::text from "better_supabase"."shipments" s where s."id" = (subject_title.subject_id)::uuid);
    when 'contract' then
      return (select s."title"::text from "better_supabase"."contracts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'control' then
      return (select s."title"::text from "better_supabase"."controls" s where s."id" = (subject_title.subject_id)::uuid);
    when 'compliance_policy' then
      return (select s."title"::text from "better_supabase"."compliance_policies" s where s."id" = (subject_title.subject_id)::uuid);
    when 'qualification_type' then
      return (select s."name"::text from "better_supabase"."qualification_types" s where s."id" = (subject_title.subject_id)::uuid);
    when 'risk' then
      return (select s."title"::text from "better_supabase"."risks" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'case' then
      return (select s."title"::text from "better_supabase"."cases" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'inspection' then
      return (select s."title"::text from "better_supabase"."inspections" s where s."id" = (subject_title.subject_id)::uuid);
    when 'inspection_program' then
      return (select s."name"::text from "better_supabase"."inspection_programs" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'inspection_finding' then
      return (select s."title"::text from "better_supabase"."inspection_findings" s where s."id" = (subject_title.subject_id)::uuid);
    when 'form' then
      return (select s."title"::text from "better_supabase"."forms" s where s."id" = (subject_title.subject_id)::uuid);
    when 'meeting' then
      return (select s."title"::text from "better_supabase"."meetings" s where s."id" = (subject_title.subject_id)::uuid);
    when 'meeting_decision' then
      return (select s."title"::text from "better_supabase"."meeting_decisions" s where s."id" = (subject_title.subject_id)::uuid);
    when 'maintenance_plan' then
      return (select s."title"::text from "better_supabase"."maintenance_plans" s where s."id" = (subject_title.subject_id)::uuid);
    when 'dam_usage_right' then
      return (select s."licensee"::text from "better_supabase"."dam_usage_rights" s where s."id" = (subject_title.subject_id)::uuid);
    when 'lims_sample' then
      return (select s."title"::text from "better_supabase"."lims_samples" s where s."id" = (subject_title.subject_id)::uuid);
    when 'tax_code' then
      return (select s."name"::text from "better_supabase"."tax_codes" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'production_order' then
      return (select s."number"::text from "better_supabase"."production_orders" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_center' then
      return (select s."name"::text from "better_supabase"."work_centers" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'bank_account' then
      return (select s."name"::text from "better_supabase"."bank_accounts" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'care_plan' then
      return (select s."title"::text from "better_supabase"."care_plans" s where s."id" = (subject_title.subject_id)::uuid);
    when 'incident' then
      return (select s."title"::text from "better_supabase"."incidents" s where s."id" = (subject_title.subject_id)::uuid);
    when 'content_entry' then
      return (select s."title"::text from "better_supabase"."content_entries" s where s."id" = (subject_title.subject_id)::uuid);
    when 'document' then
      return (select s."name"::text from "better_supabase"."documents" s where s."id" = (subject_title.subject_id)::uuid);
    when 'customer' then
      return (select s."name"::text from "public"."customers" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'drive_node' then
      return (select s."name"::text from "better_supabase"."drive_nodes" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'change_request' then
      return (select s."title"::text from "public"."change_requests" s where s."id" = (subject_title.subject_id)::uuid);
    when 'project' then
      return (select s."name"::text from "public"."projects" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'task' then
      return (select s."title"::text from "public"."tasks" s where s."id" = (subject_title.subject_id)::uuid);
    else
      return null;
  end case;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_titles (
  refs jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  found jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(subject_titles.refs) is distinct from 'array' then
    raise exception 'refs must be a JSON array of { type, id }'
      using errcode = '22023', hint = 'SUBJECT_REFS_INVALID';
  end if;
  if jsonb_array_length(subject_titles.refs) > 500 then
    raise exception 'subject_titles takes at most 500 refs'
      using errcode = '22023', hint = 'SUBJECT_REFS_TOO_MANY';
  end if;
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'message', 'id', s."id"::text,
      'title', s."body"::text, 'url', null::text))
    from "better_supabase"."messages" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'message')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'conversation', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."conversations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'conversation')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'channel', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."channels" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'channel')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'company', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."companies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'company')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'person', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."people" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'person')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'deal', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/deals'))
    from "better_supabase"."deals" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'deal')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'course', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."courses" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'course')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'post', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."posts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'post')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'activity', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."activities" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'activity')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'quote', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."quotes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'quote')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_item', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/work'))
    from "better_supabase"."work_items" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_item')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'employee', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/people'))
    from "better_supabase"."employees" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'employee')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'invoice', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."invoices" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'invoice')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'ledger_account', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."ledger_accounts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'ledger_account')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/shop'))
    from "better_supabase"."products" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product_variant', 'id', s."id"::text,
      'title', s."sku"::text, 'url', null::text))
    from "better_supabase"."product_variants" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product_variant')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'rfq', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."rfqs" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'rfq')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'till', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."tills" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'till')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'order', 'id', s."id"::text,
      'title', s."number"::text, 'url', null::text))
    from "better_supabase"."orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'calendar_event', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."calendar_events" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'calendar_event')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'booking', 'id', s."id"::text,
      'title', s."customer_name"::text, 'url', null::text))
    from "better_supabase"."bookings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'booking')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'asset', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."assets" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'asset')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'asset_location', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."asset_locations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'asset_location')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'lease', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."leases" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'lease')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'expense_report', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."expense_reports" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'expense_report')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'expense_line', 'id', s."id"::text,
      'title', s."description"::text, 'url', null::text))
    from "better_supabase"."expense_lines" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'expense_line')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'donation_fund', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."donation_funds" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'donation_fund')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_order', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."work_orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'shipment', 'id', s."id"::text,
      'title', s."reference"::text, 'url', null::text))
    from "better_supabase"."shipments" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'shipment')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'contract', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."contracts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'contract')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'control', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."controls" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'control')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'compliance_policy', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."compliance_policies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'compliance_policy')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'qualification_type', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."qualification_types" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'qualification_type')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'risk', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."risks" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'risk')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'case', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."cases" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'case')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'inspection', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."inspections" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'inspection')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'inspection_program', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."inspection_programs" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'inspection_program')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'inspection_finding', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."inspection_findings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'inspection_finding')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'form', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."forms" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'form')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'meeting', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."meetings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'meeting')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'meeting_decision', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."meeting_decisions" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'meeting_decision')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'maintenance_plan', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."maintenance_plans" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'maintenance_plan')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'dam_usage_right', 'id', s."id"::text,
      'title', s."licensee"::text, 'url', null::text))
    from "better_supabase"."dam_usage_rights" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'dam_usage_right')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'lims_sample', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."lims_samples" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'lims_sample')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'tax_code', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."tax_codes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'tax_code')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'production_order', 'id', s."id"::text,
      'title', s."number"::text, 'url', null::text))
    from "better_supabase"."production_orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'production_order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_center', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."work_centers" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_center')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'bank_account', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."bank_accounts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'bank_account')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'care_plan', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."care_plans" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'care_plan')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'incident', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."incidents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'incident')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'content_entry', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."content_entries" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'content_entry')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'document', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."documents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'document')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'customer', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/customers/' || s."id"::text))
    from "public"."customers" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'customer')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'drive_node', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."drive_nodes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'drive_node')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'application', 'id', s."id"::text,
      'title', null::text, 'url', '/people/hiring'))
    from "better_supabase"."applications" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'application')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'change_request', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/change-requests/' || s."id"::text))
    from "public"."change_requests" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'change_request')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'project', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/projects/' || s."id"::text))
    from "public"."projects" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'project')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'task', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/projects/' || s."project_id"::text))
    from "public"."tasks" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'task')::uuid[])), '[]'::jsonb);
  return found;
exception
  when invalid_text_representation then
    raise exception 'a subject id does not match its type''s id column'
      using errcode = '22023', hint = 'SUBJECT_ID_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.thread_summary (
  conversation uuid DEFAULT NULL::uuid,
  thread       uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(s) || jsonb_build_object(
    'stale', exists (
      select 1 from "better_supabase"."messages" m
      where m."conversation_id" = s."conversation_id"
        and m."kind" = 'message' and m."sent_at" is not null
        and case when s."thread_id" is null then m."thread_id" is null
          else m."id" = s."thread_id" or m."thread_id" = s."thread_id" end
        and (m."sent_at" > s."through_at"
          or m."edited_at" > s."updated_at"
          or m."archived_at" > s."updated_at")
    )
  )
  from "better_supabase"."thread_summaries" s
  where s."conversation_id" = coalesce(thread_summary.conversation,
      (select m."conversation_id" from "better_supabase"."messages" m where m."id" = thread_summary.thread))
    and s."thread_id" is not distinct from thread_summary.thread
$function$;

CREATE OR REPLACE FUNCTION better_supabase.trash_cascade (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  batch        uuid,
  depth        integer,
  actor        uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_title text;
  v_count integer := 1;
  v_child text;
  v_item "better_supabase"."trash_items"%rowtype;
begin
  case trash_cascade.subject_type
    when 'message' then
      update "better_supabase"."messages" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."body"::text into v_title;
    when 'conversation' then
      update "better_supabase"."conversations" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'deal' then
      update "better_supabase"."deals" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'work_item' then
      update "better_supabase"."work_items" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'risk' then
      update "better_supabase"."risks" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'case' then
      update "better_supabase"."cases" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."title"::text into v_title;
    when 'inspection_program' then
      update "better_supabase"."inspection_programs" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'tax_code' then
      update "better_supabase"."tax_codes" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'work_center' then
      update "better_supabase"."work_centers" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'bank_account' then
      update "better_supabase"."bank_accounts" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'customer' then
      update "public"."customers" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."organization_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'drive_node' then
      update "better_supabase"."drive_nodes" s set "archived_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."tenant_id" = trash_cascade.tenant
          and s."archived_at" is null
        returning s."name"::text into v_title;
    when 'project' then
      update "public"."projects" s set "deleted_at" = now()
        where s."id" = (trash_cascade.subject_id)::uuid
          and s."organization_id" = trash_cascade.tenant
          and s."deleted_at" is null
        returning s."name"::text into v_title;
    else
      raise exception 'this subject type has no deletedAt column' using errcode = '22023', hint = 'TRASH_UNSUPPORTED';
  end case;
  if not found then
    return 0;
  end if;
  delete from "better_supabase"."trash_items" i
    where i."subject_type" = trash_cascade.subject_type and i."subject_id" = trash_cascade.subject_id;
  insert into "better_supabase"."trash_items" ("tenant_id", "subject_type", "subject_id", "title", "batch_id", "depth", "trashed_by", "trashed_at", "purge_at")
  values (trash_cascade.tenant, trash_cascade.subject_type, trash_cascade.subject_id, v_title, trash_cascade.batch, trash_cascade.depth, trash_cascade.actor, now(), now() + make_interval(days => 30))
  returning * into v_item;
  perform "better_supabase".emit_event('subject.trashed', jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id"), 'trash-items/' || v_item."id"::text, (v_item."tenant_id")::text, null, 'better-supabase/trash');
  perform better_supabase.audit_event(
    event_type => 'subject.trashed',
    category => 'data',
    target_type => 'trash_item',
    record_id => v_item."id"::text,
    summary => 'trashed' || ' ' || v_item."subject_type" || ' ' || v_item."subject_id",
    tenant => (v_item."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id")
  );
  
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.trash_restore_batch (
  batch uuid
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_item "better_supabase"."trash_items"%rowtype;
  v_count integer := 0;
begin
  for v_item in select * from "better_supabase"."trash_items" where "batch_id" = trash_restore_batch.batch order by "depth" loop
    case v_item.subject_type
    when 'message' then
      update "better_supabase"."messages" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'conversation' then
      update "better_supabase"."conversations" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'deal' then
      update "better_supabase"."deals" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'work_item' then
      update "better_supabase"."work_items" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'risk' then
      update "better_supabase"."risks" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'case' then
      update "better_supabase"."cases" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'inspection_program' then
      update "better_supabase"."inspection_programs" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'tax_code' then
      update "better_supabase"."tax_codes" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'work_center' then
      update "better_supabase"."work_centers" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'bank_account' then
      update "better_supabase"."bank_accounts" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'customer' then
      update "public"."customers" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'drive_node' then
      update "better_supabase"."drive_nodes" s set "archived_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    when 'project' then
      update "public"."projects" s set "deleted_at" = null
        where s."id" = (v_item.subject_id)::uuid;
    else null;
  end case;
    perform "better_supabase".emit_event('subject.restored', jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id"), 'trash-items/' || v_item."id"::text, (v_item."tenant_id")::text, null, 'better-supabase/trash');
  perform better_supabase.audit_event(
    event_type => 'subject.restored',
    category => 'data',
    target_type => 'trash_item',
    record_id => v_item."id"::text,
    summary => 'restored' || ' ' || v_item."subject_type" || ' ' || v_item."subject_id",
    tenant => (v_item."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_item."tenant_id", 'subjectType', v_item."subject_type", 'subjectId', v_item."subject_id", 'id', v_item."id", 'batchId', v_item."batch_id")
  );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unread_counts (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(k."conversation_id"::text, jsonb_build_object('unread', u.unread, 'mentions', u.mentions)), '{}'::jsonb)
  from "better_supabase"."conversation_members" k
  cross join lateral (
    select count(*) as unread,
      count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) as mentions
    from "better_supabase"."messages" m
    where m."conversation_id" = k."conversation_id"
      and (m."thread_id" is null or m."broadcast")
      and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz)
      and m."archived_at" is null
      and m."author_id" is distinct from auth.uid()
  ) u
  where k."user_id" = auth.uid()
    and k."tenant_id" = unread_counts.tenant
    and not exists (select 1 from "better_supabase"."conversations" c where c."id" = k."conversation_id" and c."kind" = 'inbox')
    and u.unread > 0
$function$;
