SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."drive_grants"
  ADD COLUMN "access_request" boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION api.drive_transfer_ownership (
  tenant    uuid,
  from_user uuid,
  to_user   uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_transfer_ownership"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_record_access_requests (
  subject_type text,
  subject_id   text,
  status       text    DEFAULT NULL::text,
  page_size    integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_record_access_requests"($1, $2, $3, $4) $function$;

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
      where s."id" = (add_subject_member.subject_id)::uuid and s."deleted_at" is null;
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

CREATE OR REPLACE FUNCTION better_supabase.can_subject (
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case can_subject.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
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
    when 'engagement' then
      return exists (
        select 1 from "better_supabase"."engagements" s
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
        select 1 from "better_supabase"."lease_agreements" s
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
    when 'policy' then
      return exists (
        select 1 from "better_supabase"."policies" s
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
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
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
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
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
    when 'engagement' then
      return exists (
        select 1 from "better_supabase"."engagements" s
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
        select 1 from "better_supabase"."lease_agreements" s
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
    when 'policy' then
      return exists (
        select 1 from "better_supabase"."policies" s
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
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
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

CREATE OR REPLACE FUNCTION better_supabase.drive_access_approvers (
  subject_id text
)
  RETURNS uuid[]
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if drive_access_approvers.subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return '{}';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_access_approvers.subject_id::uuid;
  if not found then
    return '{}';
  end if;
  return coalesce((
    select array_agg(mu."user_id" order by mu."user_id")
    from "public"."memberships" mu
    where mu."organization_id" = v_node."tenant_id"
      and (exists (
        select 1 from "better_supabase"."drive_grants" gr
        where gr."node_id" = any ("better_supabase"."drive_ancestors"(v_node."id")) and (gr."expires_at" is null or gr."expires_at" > now())
          and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], gr."role"::text), 0) >= coalesce(array_position(array['viewer', 'editor', 'owner']::text[], 'owner'::text), 0)
          and ((gr."principal_type" = 'user' and gr."principal_id" = mu."user_id"::text)
      or (gr."principal_type" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = gr."principal_id"::text and tm."user_id" = mu."user_id"))
      or (gr."principal_type" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = mu."organization_id" and mr."user_id" = mu."user_id" and mr."role"::text = gr."principal_id")))
      ))
  ), '{}');
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
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_grant_access.subject_id::uuid and x."deleted_at" is null;
  if not found then
    raise exception 'item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_role is null then
    raise exception 'action must be read, comment or write' using errcode = '22023', hint = 'DRIVE_ROLE_UNKNOWN';
  end if;
  if drive_grant_access.ends_at is not null and drive_grant_access.ends_at <= now() then
    delete from "better_supabase"."drive_grants" dg where dg."node_id" = v_node."id" and dg."principal_type" = 'user' and dg."principal_id" = drive_grant_access.user_id::text and dg."access_request";
    if found then
      perform "better_supabase".emit_event('drive.node_unshared', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', 'user', 'principalId', drive_grant_access.user_id::text), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_unshared',
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
  perform "better_supabase".emit_event('drive.node_shared', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'principalType', 'user', 'principalId', drive_grant_access.user_id::text, 'role', v_role), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_shared',
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

CREATE OR REPLACE FUNCTION better_supabase.drive_guest_sharing()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."subject_type" = 'drive_node'
    and ("better_supabase"."drive_sharing"(new."tenant_id") ->> 'guests')::boolean is false then
    raise exception 'this organization has turned off sharing drive items with guests' using errcode = '42501', hint = 'DRIVE_SHARING_DISABLED';
  end if;
  return new;
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
  where x."tenant_id" = drive_insert_node.tenant and x."parent_id" is not distinct from drive_insert_node.parent and x."deleted_at" is null;
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
  perform "better_supabase".emit_event('drive.node_created', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'kind', v_node."kind", 'name', v_node."name", 'parentId', v_node."parent_id", 'source', drive_insert_node.source), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_created',
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
    and x."tenant_id"::text = v_tenant and x."deleted_at" is null;
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
      from (select y as r from "better_supabase"."drive_nodes" y where y."parent_id" = v_node."id" and y."deleted_at" is null order by (y."kind" = 'folder') desc, y."rank", lower(y."name"), y."id" limit 500) c
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
    and x."tenant_id"::text = v_link ->> 'organizationId' and x."deleted_at" is null;
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
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_move.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to move this item' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (coalesce(v_node."source"::text, 'internal') not in ('internal', 'request') or false) then
    raise exception 'this item mirrors an external account and is read-only' using errcode = '42501', hint = 'DRIVE_READ_ONLY';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
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
      where x."tenant_id" = v_node."tenant_id" and x."parent_id" is not distinct from drive_move.parent and x."deleted_at" is null;
    end if;
    update "better_supabase"."drive_nodes" x set "parent_id" = drive_move.parent, "name" = v_name, "rank" = coalesce(drive_move.rank, case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end), "updated_at" = now()
    where x."id" = v_node."id"
    returning * into v_node;
    perform "better_supabase".emit_event('drive.node_moved', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'parentId', v_node."parent_id", 'previousParentId', v_previous), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_moved',
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

CREATE OR REPLACE FUNCTION better_supabase.drive_share_link_allowed (
  node   text,
  tenant text,
  role   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  if drive_share_link_allowed.node !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x
  where x."id" = drive_share_link_allowed.node::uuid and x."tenant_id"::text = drive_share_link_allowed.tenant::text;
  if not found or not "better_supabase"."drive_can"(v_node."id", 'owner') then
    return false;
  end if;
  if drive_share_link_allowed.role = 'upload' and v_node."kind" <> 'folder' then
    raise exception 'an upload link names a folder' using errcode = '22023', hint = 'DRIVE_LINK_ROLE_INVALID';
  end if;
  if "better_supabase"."drive_sharing"(v_node."tenant_id") ->> 'links' = 'none' then
    raise exception 'this organization has turned off share links' using errcode = '42501', hint = 'DRIVE_SHARING_DISABLED';
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_sharing (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select '{"guests": true, "links": "anyone"}'::jsonb || coalesce("better_supabase"."organization_setting"(drive_sharing.tenant, 'drive.sharing'), '{}'::jsonb)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_transfer_ownership (
  tenant    uuid,
  from_user uuid,
  to_user   uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_grant "better_supabase"."drive_grants"%rowtype;
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_drive_ids uuid[] := '{}';
  v_nodes integer := 0;
  v_drives integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', drive_transfer_ownership.tenant, 'drive.manage'), false)) then
    raise exception 'you can''t transfer items in this organization' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_transfer_ownership.from_user is null or drive_transfer_ownership.to_user is null
    or drive_transfer_ownership.from_user = drive_transfer_ownership.to_user then
    raise exception 'name two different users to transfer between' using errcode = '22023', hint = 'DRIVE_TRANSFER_INVALID';
  end if;
  if not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = drive_transfer_ownership.tenant and mu."user_id" = drive_transfer_ownership.to_user
  ) then
    raise exception 'the new owner is not an active member of this organization' using errcode = 'P0002', hint = 'DRIVE_PRINCIPAL_NOT_FOUND';
  end if;
  for v_grant in
    select gr.* from "better_supabase"."drive_grants" gr
    where gr."tenant_id" = drive_transfer_ownership.tenant and gr."role"::text = 'owner'
      and gr."principal_type" = 'user' and gr."principal_id" = drive_transfer_ownership.from_user::text
  loop
    delete from "better_supabase"."drive_grants" gr where gr."node_id" = v_grant."node_id" and gr."principal_type" = 'user' and gr."principal_id" = drive_transfer_ownership.to_user::text;
    update "better_supabase"."drive_grants" set "principal_id" = drive_transfer_ownership.to_user::text where "id" = v_grant."id";
    select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_grant."node_id";
    v_nodes := v_nodes + 1;
    perform "better_supabase".emit_event('drive.node_ownership_transferred', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'fromUserId', drive_transfer_ownership.from_user::text, 'toUserId', drive_transfer_ownership.to_user::text), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive');
  perform better_supabase.audit_event(
    event_type => 'drive.node_ownership_transferred',
    category => 'access',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'ownership transferred',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'fromUserId', drive_transfer_ownership.from_user::text, 'toUserId', drive_transfer_ownership.to_user::text)
  );
  end loop;
  return jsonb_build_object('nodes', v_nodes, 'drives', v_drives);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.end_access (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  SET "IntervalStyle" TO 'iso_8601'
  AS $function$
declare
  v_row "better_supabase"."access_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."access_requests" r where r."id" = end_access.request_id for update;
  if not found then
    raise exception 'access request not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'access_requests.manage'), false)) then
    raise exception 'not allowed to end this access' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if v_row."granted_at" is null or v_row."ended_at" is not null then
    raise exception 'this access isn''t active' using errcode = '22023', hint = 'ACCESS_NOT_GRANTED';
  end if;
  if v_row."target" = 'record' then
    case v_row."subject_type"
    when 'drive_node' then
      perform "better_supabase"."drive_grant_access"(v_row."subject_id", v_row."user_id", v_row."action", now());
    else
      if v_row."member_id" is not null then
        perform "better_supabase"."close_subject_member"(v_row."member_id");
      end if;
    end case;
  else
    -- Only a role that is still the granted one goes back; a later change wins.
    if exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
        and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = v_row."role"
    ) then
      if v_row."previous_role" is null then
        delete from "public"."memberships" where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
      else
        update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."previous_role")::text or r."key" = (v_row."previous_role")::text) order by (r."id"::text = (v_row."previous_role")::text) desc limit 1)
        where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
      end if;
    end if;
  end if;
  update "better_supabase"."access_requests" r set "ended_at" = now() where r."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('access.ended', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', 'revoked'), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access.ended',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', 'revoked')
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'ended', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.grant_access_request (
  request_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."access_requests"%rowtype;
  v_previous text;
  v_ends timestamptz;
  v_member uuid;
begin
  select * into v_row from "better_supabase"."access_requests" r where r."id" = grant_access_request.request_id for update;
  if not found or v_row."granted_at" is not null then
    return;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  if v_row."target" = 'record' then
    v_ends := now() + v_row."duration";
    case v_row."subject_type"
    when 'drive_node' then
      perform "better_supabase"."drive_grant_access"(v_row."subject_id", v_row."user_id", v_row."action", v_ends);
    else
      v_member := "better_supabase"."grant_subject_member"(v_row."subject_type", v_row."subject_id", v_row."user_id", v_ends, v_row."emergency", v_row."reason");
    end case;
    update "better_supabase"."access_requests" r
    set "granted_at" = now(), "expires_at" = v_ends, "member_id" = v_member
    where r."id" = v_row."id"
    returning * into v_row;
    if not v_row."emergency" then
      perform "better_supabase".emit_event('access.request_approved', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access.request_approved',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action")
  );
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
    return;
  end if;
  select (select r."key" from "better_supabase"."roles" r where r."id" = m."role") into v_previous from "public"."memberships" m
  where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  for update;
  if found then
    update "public"."memberships" set "role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."role")::text or r."key" = (v_row."role")::text) order by (r."id"::text = (v_row."role")::text) desc limit 1)
    where "organization_id" = v_row."tenant_id" and "user_id" = v_row."user_id";
  else
    insert into "public"."memberships" ("organization_id", "user_id", "role")
    values (v_row."tenant_id", v_row."user_id", (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_row."role")::text or r."key" = (v_row."role")::text) order by (r."id"::text = (v_row."role")::text) desc limit 1));
  end if;
  update "better_supabase"."access_requests" r
  set "previous_role" = v_previous,
      "granted_at" = now(),
      "expires_at" = case when v_row."duration" is null then null else now() + v_row."duration" end
  where r."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('access.request_approved', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access.request_approved',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_access_grant"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.link (
  tenant      uuid,
  kind        text,
  source_type text,
  source_id   text,
  target_type text,
  target_id   text,
  data        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_kind text;
  v_inverted boolean;
  v_acyclic boolean;
  v_single boolean;
  v_symmetric boolean;
  v_source_type text;
  v_source_id text;
  v_target_type text;
  v_target_id text;
  v_id uuid;
  v_created boolean := false;
  v_previous jsonb;
  v_replaced jsonb;
  v_old "better_supabase"."relations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', link.tenant, 'relations.manage'), false)) then
    raise exception 'not allowed to link records' using errcode = '42501', hint = 'RELATION_FORBIDDEN';
  end if;
  if link.data is not null and jsonb_typeof(link.data) <> 'object' then
    raise exception 'data must be an object' using errcode = '22023', hint = 'RELATION_INVALID';
  end if;
  if link.source_type = link.target_type and link.source_id = link.target_id then
    raise exception 'a record can''t link to itself' using errcode = '22023', hint = 'RELATION_SELF';
  end if;

  select k.canonical, k.inverted, k.acyclic, k.single, k.both_ways
    into v_kind, v_inverted, v_acyclic, v_single, v_symmetric
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from'), ('variant_of', 'variant_of', false, true, true, false, 'variants'), ('variants', 'variant_of', true, true, true, false, 'variant_of'), ('represents', 'represents', false, false, false, false, 'represented_by'), ('represented_by', 'represents', true, false, false, false, 'represents'), ('mitigated_by', 'mitigated_by', false, false, false, false, 'mitigates'), ('mitigates', 'mitigated_by', true, false, false, false, 'mitigated_by'), ('materialized_as', 'materialized_as', false, false, false, false, 'materializes'), ('materializes', 'materialized_as', true, false, false, false, 'materialized_as')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = link.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  if v_inverted then
    v_source_type := link.target_type; v_source_id := link.target_id;
    v_target_type := link.source_type; v_target_id := link.source_id;
  else
    v_source_type := link.source_type; v_source_id := link.source_id;
    v_target_type := link.target_type; v_target_id := link.target_id;
  end if;
  if v_symmetric and (v_source_type, v_source_id) > (v_target_type, v_target_id) then
    select v_target_type, v_target_id, v_source_type, v_source_id
      into v_source_type, v_source_id, v_target_type, v_target_id;
  end if;
  if v_kind = 'variant_of' and not (v_source_type in ('drive_node') and v_target_type in ('drive_node')) then
    raise exception 'this kind of link doesn''t accept these record types' using errcode = '22023', hint = 'RELATION_TYPE_NOT_ALLOWED';
  end if;
  if v_kind = 'represents' and not (v_source_type in ('person') and v_target_type in ('customer', 'drive_node')) then
    raise exception 'this kind of link doesn''t accept these record types' using errcode = '22023', hint = 'RELATION_TYPE_NOT_ALLOWED';
  end if;
  if v_kind = 'mitigated_by' and not (v_source_type in ('risk') and v_target_type in ('control', 'work_item', 'drive_node')) then
    raise exception 'this kind of link doesn''t accept these record types' using errcode = '22023', hint = 'RELATION_TYPE_NOT_ALLOWED';
  end if;
  if v_kind = 'materialized_as' and not (v_source_type in ('risk') and v_target_type in ('case')) then
    raise exception 'this kind of link doesn''t accept these record types' using errcode = '22023', hint = 'RELATION_TYPE_NOT_ALLOWED';
  end if;
  if not (case link.source_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'compliance.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'risks.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant and (coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    else false
  end)
     or not (case link.target_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'compliance.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'risks.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant and (coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    else false
  end) then
    raise exception 'not allowed to link these records' using errcode = '42501', hint = 'RELATION_SUBJECT_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_relation_link"(uuid, text, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text, $6::text)', v_hook::oid::regproc)
        using link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id;
    end if;
  end;
  if v_acyclic or v_single then
    perform pg_advisory_xact_lock(hashtext(link.tenant::text || ':relation:' || v_kind));
  end if;
  select "id", "data" into v_id, v_previous from "better_supabase"."relations"
    where "tenant_id" = link.tenant and "kind" = v_kind
      and "source_type" = v_source_type and "source_id" = v_source_id
      and "target_type" = v_target_type and "target_id" = v_target_id;
  if v_id is null then
    if v_kind = 'represents' and not coalesce((jsonb_typeof(coalesce(link.data, '{}'::jsonb)) = 'object'
      and (coalesce(link.data, '{}'::jsonb) ->> 'role') in ('legal_representative', 'guardian', 'mentor', 'curator', 'parent', 'contact_person', 'emergency_contact', 'other')
      and (coalesce(link.data, '{}'::jsonb) ->> 'authority') in ('inform', 'act')
      and (coalesce(link.data, '{}'::jsonb) -> 'valid_from' is null or (jsonb_typeof(coalesce(link.data, '{}'::jsonb) -> 'valid_from') = 'string' and pg_input_is_valid(coalesce(link.data, '{}'::jsonb) ->> 'valid_from', 'date')))
      and (coalesce(link.data, '{}'::jsonb) -> 'valid_until' is null or (jsonb_typeof(coalesce(link.data, '{}'::jsonb) -> 'valid_until') = 'string' and pg_input_is_valid(coalesce(link.data, '{}'::jsonb) ->> 'valid_until', 'date')))
      and case when pg_input_is_valid(coalesce(link.data, '{}'::jsonb) ->> 'valid_from', 'date') and pg_input_is_valid(coalesce(link.data, '{}'::jsonb) ->> 'valid_until', 'date')
        then (coalesce(link.data, '{}'::jsonb) ->> 'valid_from')::date <= (coalesce(link.data, '{}'::jsonb) ->> 'valid_until')::date else true end), false) then
      raise exception 'this kind of link doesn''t accept this data' using errcode = '22023', hint = 'RELATION_DATA_INVALID';
    end if;
    if v_acyclic and exists (
      with recursive reach(t, i, depth) as (
        select v_target_type, v_target_id, 0
        union
        select r."target_type", r."target_id", reach.depth + 1
        from "better_supabase"."relations" r join reach
          on r."source_type" = reach.t and r."source_id" = reach.i
        where r."tenant_id" = link.tenant and r."kind" = v_kind and reach.depth < 1000
      )
      select 1 from reach where t = v_source_type and i = v_source_id
    ) then
      raise exception 'this link would create a cycle' using errcode = '23514', hint = 'RELATION_CYCLE';
    end if;
    if v_single then
      delete from "better_supabase"."relations"
        where "tenant_id" = link.tenant and "kind" = v_kind
          and "source_type" = v_source_type and "source_id" = v_source_id
        returning * into v_old;
      if v_old."id" is not null then
        v_replaced := jsonb_build_object('targetType', v_old."target_type", 'targetId', v_old."target_id", 'data', v_old."data");
        perform "better_supabase".emit_event('subject.unlinked', jsonb_build_object('organizationId', link.tenant, 'id', v_old."id", 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_old."target_type", 'targetId', v_old."target_id"), 'subjects/' || v_source_type || '/' || v_source_id, (link.tenant)::text, null, 'better-supabase/relations');
      end if;
    end if;
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "data", "created_by")
    values (link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id, coalesce(link.data, '{}'::jsonb), auth.uid())
    returning "id" into v_id;
    v_created := true;
    perform "better_supabase".emit_event('subject.linked', jsonb_build_object('organizationId', link.tenant, 'id', v_id, 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_target_type, 'targetId', v_target_id), 'subjects/' || v_source_type || '/' || v_source_id, (link.tenant)::text, null, 'better-supabase/relations');
  elsif link.data is not null then
    if v_kind = 'represents' and not coalesce((jsonb_typeof(link.data) = 'object'
      and (link.data ->> 'role') in ('legal_representative', 'guardian', 'mentor', 'curator', 'parent', 'contact_person', 'emergency_contact', 'other')
      and (link.data ->> 'authority') in ('inform', 'act')
      and (link.data -> 'valid_from' is null or (jsonb_typeof(link.data -> 'valid_from') = 'string' and pg_input_is_valid(link.data ->> 'valid_from', 'date')))
      and (link.data -> 'valid_until' is null or (jsonb_typeof(link.data -> 'valid_until') = 'string' and pg_input_is_valid(link.data ->> 'valid_until', 'date')))
      and case when pg_input_is_valid(link.data ->> 'valid_from', 'date') and pg_input_is_valid(link.data ->> 'valid_until', 'date')
        then (link.data ->> 'valid_from')::date <= (link.data ->> 'valid_until')::date else true end), false) then
      raise exception 'this kind of link doesn''t accept this data' using errcode = '22023', hint = 'RELATION_DATA_INVALID';
    end if;
    update "better_supabase"."relations" set "data" = link.data where "id" = v_id;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_relation_link"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object(
    'id', v_id, 'kind', v_kind, 'created', v_created,
    'sourceType', v_source_type, 'sourceId', v_source_id,
    'targetType', v_target_type, 'targetId', v_target_id,
    'previousData', case when v_created then null else v_previous end,
    'replaced', v_replaced);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_record_access_requests (
  subject_type text,
  subject_id   text,
  status       text    DEFAULT NULL::text,
  page_size    integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  SET "IntervalStyle" TO 'iso_8601'
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_all boolean;
begin
  v_tenant := "better_supabase"."record_team_tenant"(list_record_access_requests.subject_type, list_record_access_requests.subject_id);
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  v_all := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'access_requests.read'), false)
    or coalesce(auth.uid() = any ("better_supabase"."record_team_leads"(list_record_access_requests.subject_type, list_record_access_requests.subject_id)), false)
    or coalesce(auth.uid() = any (case list_record_access_requests.subject_type
      when 'drive_node' then "better_supabase"."drive_access_approvers"(list_record_access_requests.subject_id)
      end), false);
  return (
    select coalesce(jsonb_agg(item order by created desc), '[]'::jsonb)
    from (
      select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'role', r."role", 'target', r."target", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'action', r."action", 'emergency', r."emergency", 'review', case when r."reviewed_at" is null then null else jsonb_build_object('verdict', r."review_verdict", 'note', r."review_note", 'reviewedBy', r."reviewed_by", 'reviewedAt', r."reviewed_at") end, 'previousRole', r."previous_role", 'reason', r."reason", 'duration', r."duration"::text, 'status', case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end, 'approvalId', r."approval_id", 'grantedAt', r."granted_at", 'expiresAt', r."expires_at", 'endedAt', r."ended_at", 'createdAt', r."created_at") as item, r."created_at" as created
      from "better_supabase"."access_requests" r
      left join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
      where r."tenant_id" = v_tenant and r."target" = 'record'
        and r."subject_type" = list_record_access_requests.subject_type and r."subject_id" = list_record_access_requests.subject_id
        and (v_all or r."user_id" = auth.uid())
        and (list_record_access_requests.status is null or case when r."ended_at" is not null then 'ended' when r."granted_at" is not null then 'granted' else coalesce(x."status", 'pending') end = list_record_access_requests.status)
      order by r."created_at" desc
      limit least(greatest(coalesce(list_record_access_requests.page_size, 50), 1), 200)
    ) items
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_emergency_access (
  subject_type text,
  subject_id   text,
  reason       text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  SET "IntervalStyle" TO 'iso_8601'
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_row "better_supabase"."access_requests"%rowtype;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to open emergency access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  if length(btrim(coalesce(open_emergency_access.reason, ''))) < 10 then
    raise exception 'say why you need emergency access, in at least 10 characters' using errcode = '22023', hint = 'ACCESS_REQUEST_REASON_REQUIRED';
  end if;
  if not (open_emergency_access.subject_type = any (array['customer', 'drive_node']::text[])) or (case open_emergency_access.subject_type
      when 'customer' then not ('read' = any (array['read', 'write']::text[]))
      when 'drive_node' then not ('read' = any (array['read']::text[]))
      else true end) then
    raise exception 'this record or action can''t be requested' using errcode = '22023', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  v_tenant := "better_supabase"."record_team_tenant"(open_emergency_access.subject_type, open_emergency_access.subject_id);
  if v_tenant is null then
    raise exception 'record not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  if not exists (select 1 from "public"."memberships" m where m."organization_id" = v_tenant and m."user_id" = auth.uid()) or not coalesce(better_supabase.can('tenant', v_tenant, 'access_requests.emergency'), false) then
    raise exception 'not allowed to open emergency access here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  insert into "better_supabase"."access_requests" ("tenant_id", "user_id", "target", "subject_type", "subject_id", "action", "emergency", "reason", "duration")
  values (v_tenant, v_me, 'record', open_emergency_access.subject_type, open_emergency_access.subject_id, 'read', true, btrim(open_emergency_access.reason), interval '8 hours')
  returning * into v_row;
  perform "better_supabase"."grant_access_request"(v_row."id");
  select * into v_row from "better_supabase"."access_requests" r where r."id" = v_row."id";
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'access_request.emergency_opened',
      'tenant', v_tenant,
      'actor', v_me,
      'subject_type', open_emergency_access.subject_type,
      'subject_id', open_emergency_access.subject_id,
      'summary', btrim(open_emergency_access.reason),
      'recipients', to_jsonb("better_supabase"."record_team_leads"(open_emergency_access.subject_type, open_emergency_access.subject_id)),
      'permission', 'access_requests.review',
      'watchers', false,
      'key', 'access_request.emergency_opened:' || v_row."id"::text,
      'data', jsonb_build_object('accessRequestId', v_row."id")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform "better_supabase".emit_event('access_request.emergency_opened', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', v_row."reason"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access_request.emergency_opened',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'reason', v_row."reason")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'granted', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
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
      where s."id" = (record_team_tenant.subject_id)::uuid and s."deleted_at" is null;
    else
      v_tenant := null;
  end case;
  return v_tenant;
exception
  when invalid_text_representation then
    return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_record_access (
  subject_type text,
  subject_id   text,
  action       text     DEFAULT 'read'::text,
  reason       text     DEFAULT NULL::text,
  duration     interval DEFAULT '7 days'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  SET "IntervalStyle" TO 'iso_8601'
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_duration interval := coalesce(request_record_access.duration, interval '7 days');
  v_leads uuid[];
  v_row "better_supabase"."access_requests"%rowtype;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to request access' using errcode = '42501', hint = 'ACCESS_SIGN_IN';
  end if;
  if not (request_record_access.subject_type = any (array['customer', 'drive_node']::text[])) or (case request_record_access.subject_type
      when 'customer' then not (request_record_access.action = any (array['read', 'write']::text[]))
      when 'drive_node' then not (request_record_access.action = any (array['read']::text[]))
      else true end) then
    raise exception 'this record or action can''t be requested' using errcode = '22023', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  v_tenant := "better_supabase"."record_team_tenant"(request_record_access.subject_type, request_record_access.subject_id);
  if v_tenant is null then
    raise exception 'record not found' using errcode = 'P0002', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  if not exists (select 1 from "public"."memberships" m where m."organization_id" = v_tenant and m."user_id" = auth.uid()) or not coalesce(better_supabase.can('tenant', v_tenant, 'access_requests.create'), false) then
    raise exception 'not allowed to request access here' using errcode = '42501', hint = 'ACCESS_REQUEST_FORBIDDEN';
  end if;
  if "better_supabase"."can_subject"(request_record_access.subject_type, request_record_access.subject_id, request_record_access.action) then
    raise exception 'you already have this access' using errcode = '22023', hint = 'ACCESS_REQUEST_RECORD_INVALID';
  end if;
  if v_duration <= interval '0' then
    raise exception 'duration must be positive' using errcode = '22023', hint = 'ACCESS_DURATION_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_record_access.subject_type || ':' || request_record_access.subject_id || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."access_requests" r join "better_supabase"."approval_requests" x on x."id" = r."approval_id"
    where r."subject_type" = request_record_access.subject_type and r."subject_id" = request_record_access.subject_id
      and r."user_id" = v_me and x."status" = 'pending'
  ) then
    raise exception 'you already have a pending access request for this record' using errcode = '23505', hint = 'ACCESS_REQUEST_PENDING';
  end if;
  insert into "better_supabase"."access_requests" ("tenant_id", "user_id", "target", "subject_type", "subject_id", "action", "reason", "duration")
  values (v_tenant, v_me, 'record', request_record_access.subject_type, request_record_access.subject_id, request_record_access.action, request_record_access.reason, v_duration)
  returning * into v_row;
  v_leads := "better_supabase"."record_team_leads"(request_record_access.subject_type, request_record_access.subject_id);
  if coalesce(cardinality(v_leads), 0) = 0 then
    v_leads := case request_record_access.subject_type
      when 'drive_node' then array_remove("better_supabase"."drive_access_approvers"(request_record_access.subject_id), v_me)
      else v_leads end;
  end if;
  v_approval := "better_supabase"."open_approval"(
    v_tenant, 'access_request', v_row."id"::text, 'grant',
    '{"steps":[{"approvers":{"permission":"members.update_role"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb || jsonb_build_object('steps', jsonb_build_array(jsonb_build_object(
      'approvers', case when cardinality(v_leads) > 0 then jsonb_build_object('users', to_jsonb(v_leads)) else jsonb_build_object('permission', 'subjects.manage') end,
      'required', 1))),
    request_record_access.reason,
    jsonb_build_object('subjectType', request_record_access.subject_type, 'subjectId', request_record_access.subject_id, 'action', request_record_access.action, 'userId', v_me, 'duration', v_duration::text)
  );
  update "better_supabase"."access_requests" r set "approval_id" = (v_approval ->> 'id')::uuid
  where r."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('access.requested', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action"), 'access-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/access-requests');
  perform better_supabase.audit_event(
    event_type => 'access.requested',
    category => 'membership',
    target_type => 'user',
    record_id => v_row."user_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'role', v_row."role", 'id', v_row."id", 'approvalId', v_row."approval_id", 'expiresAt', v_row."expires_at", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'role', v_row."role", 'target', v_row."target", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'action', v_row."action", 'emergency', v_row."emergency", 'review', case when v_row."reviewed_at" is null then null else jsonb_build_object('verdict', v_row."review_verdict", 'note', v_row."review_note", 'reviewedBy', v_row."reviewed_by", 'reviewedAt', v_row."reviewed_at") end, 'previousRole', v_row."previous_role", 'reason', v_row."reason", 'duration', v_row."duration"::text, 'status', 'pending', 'approvalId', v_row."approval_id", 'grantedAt', v_row."granted_at", 'expiresAt', v_row."expires_at", 'endedAt', v_row."ended_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE TRIGGER bsb_drive_guest_sharing
  BEFORE INSERT OR UPDATE OF subject_type, subject_id ON better_supabase.guest_grants
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.drive_guest_sharing();

REVOKE ALL ON FUNCTION "api"."drive_transfer_ownership"(uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_transfer_ownership"(uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_record_access_requests"(text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_record_access_requests"(text, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_access_approvers"(text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."drive_grant_access"(text, uuid, text, timestamp WITH time zone) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."drive_guest_sharing"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."drive_sharing"(uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."drive_transfer_ownership"(uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_transfer_ownership"(uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_record_access_requests"(text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_record_access_requests"(text, text, text, integer) TO "authenticated", "service_role";
