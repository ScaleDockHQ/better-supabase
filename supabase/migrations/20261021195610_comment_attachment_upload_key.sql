SET local check_function_bodies = off;

DROP POLICY "attachments_insert" ON "better_supabase"."attachments";

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
    when 'comment' then
      return exists (
        select 1 from "better_supabase"."comments" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."organization_id", 'comments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."organization_id", 'comments.create'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."organization_id", 'comments.create'), false)
          else true
        end)
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.write'), false)
          else true
        end)
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.write'), false)
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
    when 'engagement' then
      return exists (
        select 1 from "better_supabase"."engagements" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'engagements.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'engagements.write'), false)
          else true
        end)
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'work_items.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'work_items.write'), false)
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
          when 'read' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.write'), false)
          else true
        end)
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.manage'), false)
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
    when 'comment' then
      return exists (
        select 1 from "better_supabase"."comments" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'comments.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'comments.create'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'comments.create'), false)
          else false
        end
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.write'), false)
          else false
        end
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.write'), false)
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
    when 'engagement' then
      return exists (
        select 1 from "better_supabase"."engagements" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'engagements.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'engagements.write'), false)
          else false
        end
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'work_items.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'work_items.write'), false)
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
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.write'), false)
          else false
        end
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.manage'), false)
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

CREATE POLICY "attachments_insert" ON "better_supabase"."attachments"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((uploaded_by = ( SELECT auth.uid() AS uid)) AND COALESCE(better_supabase.can('tenant'::text, organization_id,
CASE subject_type
    WHEN 'comment'::text THEN 'comments.create'::text
    ELSE 'attachments.upload'::text
END), false) AND better_supabase.attachment_subject_readable(subject_type, subject_id, organization_id) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));
