SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.list_roles (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_roles"($1) $function$;

CREATE OR REPLACE FUNCTION api.set_permission_override (
  tenant     uuid,
  role       text,
  permission text,
  granted    boolean
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_permission_override"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_roles (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), list_roles.tenant, 'members.read'), false)) then
    raise exception 'Not allowed to read roles' using errcode = '42501', hint = 'PERMISSIONS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r."id",
      'key', r."key",
      'members', (select count(*) from "public"."memberships" mm where mm."organization_id" = list_roles.tenant and mm."role" = r."id"),
      'default_permissions', coalesce((
        select jsonb_agg(p."key" order by p."key")
        from "better_supabase"."role_permissions" x join "better_supabase"."permissions" p on p."id" = x."permission_id"
        where x."role_id" = r."id"
      ), '[]'::jsonb),
      'permissions', coalesce((
        select jsonb_agg(p."key" order by p."key")
        from "better_supabase"."permissions" p
        where coalesce(
          (select bool_and(ov."granted") from "better_supabase"."permission_overrides" ov
            where ov."organization_id" = list_roles.tenant and ov."role_id" = r."id" and ov."permission_id" = p."id"),
          exists (select 1 from "better_supabase"."role_permissions" x where x."role_id" = r."id" and x."permission_id" = p."id")
        )
      ), '[]'::jsonb),
      'overrides', coalesce((
        select jsonb_agg(jsonb_build_object('permission', p."key", 'granted', ov."granted") order by p."key")
        from "better_supabase"."permission_overrides" ov join "better_supabase"."permissions" p on p."id" = ov."permission_id"
        where ov."organization_id" = list_roles.tenant and ov."role_id" = r."id"
      ), '[]'::jsonb)
    ) order by r."key")
    from "better_supabase"."roles" r
    where true and r."scope"::text = 'tenant'
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case op
    when 'access-requests.create' then 'access_requests.create'
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'activities.manage' then 'engagements.manage'
    when 'activities.read' then 'engagements.read'
    when 'activities.write' then 'engagements.write'
    when 'agents.create' then 'ai.create'
    when 'agents.moderate' then 'ai.moderate'
    when 'agents.publish' then 'ai.share'
    when 'agents.read' then 'ai.read'
    when 'ai-chat.admin' then 'ai_chat.admin'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai.admin'
    when 'ai-files.upload' then 'ai.create'
    when 'ai-keys.manage' then 'ai.admin'
    when 'ai-keys.use' then 'ai.create'
    when 'ai-schedules.create' then 'ai.create'
    when 'ai-schedules.manage' then 'ai.admin'
    when 'announcements.manage' then 'announcements.manage'
    when 'api-keys.manage' then 'api_keys.manage'
    when 'api-keys.own' then 'api_keys.own'
    when 'approvals.manage' then 'approvals.manage'
    when 'approvals.read' then 'approvals.read'
    when 'approvals.request' then 'approvals.request'
    when 'assets.assign' then 'assets.assign'
    when 'assets.manage' then 'assets.manage'
    when 'assets.read' then 'assets.read'
    when 'assignment.assign' then 'assignment.assign'
    when 'assignment.manage' then 'assignment.manage'
    when 'assignment.read' then 'assignment.read'
    when 'attachments.manage' then 'attachments.manage'
    when 'attachments.read' then 'attachments.read'
    when 'attachments.upload' then 'attachments.upload'
    when 'audit.revert' then 'audit.revert'
    when 'audit.view' then 'audit.read'
    when 'audit.viewAll' then 'audit.read'
    when 'automations.admin' then 'rules.admin'
    when 'automations.edit' then 'rules.edit'
    when 'automations.publish' then 'rules.publish'
    when 'automations.read' then 'rules.read'
    when 'billable-time.invoice' then 'billable_time.invoice'
    when 'billable-time.manage' then 'billable_time.manage'
    when 'billable-time.read' then 'billable_time.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk.run' then 'bulk.run'
    when 'calendar.manage' then 'calendar.manage'
    when 'calendar.read' then 'calendar.read'
    when 'calendar.write' then 'calendar.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'compliance.acknowledge' then 'controls.acknowledge'
    when 'compliance.collect' then 'controls.collect'
    when 'compliance.manage' then 'controls.manage'
    when 'compliance.read' then 'controls.read'
    when 'connectors.manage' then 'ai.admin'
    when 'connectors.read' then 'ai.read'
    when 'connectors.use' then 'ai.create'
    when 'contacts.manage' then 'parties.manage'
    when 'contacts.read' then 'parties.read'
    when 'contacts.write' then 'parties.write'
    when 'content.publish' then 'content.publish'
    when 'content.read' then 'content.read'
    when 'content.write' then 'content.write'
    when 'contracts.manage' then 'contracts.manage'
    when 'contracts.read' then 'contracts.read'
    when 'contracts.write' then 'contracts.write'
    when 'courses.enroll' then 'courses.enroll'
    when 'courses.manage' then 'courses.manage'
    when 'courses.read' then 'courses.read'
    when 'custom-fields.manage' then 'custom_fields.manage'
    when 'custom-fields.read' then 'custom_fields.read'
    when 'custom-fields.sensitive' then 'custom_fields.sensitive.read'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'organization.export'
    when 'deals.manage' then 'deals.manage'
    when 'deals.read' then 'deals.read'
    when 'deals.write' then 'deals.write'
    when 'dispatch.manage' then 'dispatch.manage'
    when 'dispatch.read' then 'dispatch.read'
    when 'dispatch.work' then 'dispatch.work'
    when 'documents.manage' then 'documents.manage'
    when 'documents.read' then 'documents.read'
    when 'documents.suggest' then 'documents.suggest'
    when 'documents.write' then 'documents.write'
    when 'donations.manage' then 'donations.manage'
    when 'donations.read' then 'donations.read'
    when 'drive.create' then 'drive.create'
    when 'drive.manage' then 'drive.manage'
    when 'drive.read' then 'drive.read'
    when 'employees.read' then 'employees.read'
    when 'employees.viewSensitive' then 'employees.view_sensitive'
    when 'employees.write' then 'employees.write'
    when 'enrichment.read' then 'enrichment.read'
    when 'enrichment.run' then 'enrichment.run'
    when 'enrollments.enroll' then 'enrollments.enroll'
    when 'enrollments.manage' then 'enrollments.manage'
    when 'enrollments.read' then 'enrollments.read'
    when 'expenses.approve' then 'expenses.approve'
    when 'expenses.manage' then 'expenses.manage'
    when 'expenses.read' then 'expenses.read'
    when 'expenses.submit' then 'expenses.submit'
    when 'field-history.read' then 'history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'goals.manage' then 'targets.manage'
    when 'goals.read' then 'targets.read'
    when 'guests.manage' then 'guests.manage'
    when 'guests.read' then 'guests.read'
    when 'hiring.manage' then 'hiring.manage'
    when 'hiring.read' then 'hiring.read'
    when 'hiring.write' then 'hiring.write'
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invitations.view' then 'members.invite'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'ai.admin'
    when 'knowledge.read' then 'ai.read'
    when 'knowledge.write' then 'ai.create'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'mail-sync.connect' then 'mail.connect'
    when 'mail-sync.manage' then 'mail.manage'
    when 'mail-sync.read' then 'mail.read'
    when 'mail-sync.send' then 'mail.send'
    when 'memory.manage' then 'ai.admin'
    when 'memory.read' then 'ai.read'
    when 'messaging.moderate' then 'messages.moderate'
    when 'messaging.read' then 'messages.read'
    when 'messaging.send' then 'messages.send'
    when 'metrics.manage' then 'metrics.manage'
    when 'metrics.read' then 'metrics.read'
    when 'moderation.ban' then 'moderation.ban'
    when 'moderation.manage' then 'moderation.manage'
    when 'moderation.read' then 'moderation.read'
    when 'moderation.report' then 'moderation.report'
    when 'notifications.read' then 'notifications.read'
    when 'notifications.send' then 'notifications.send'
    when 'numbering.assign' then 'number_sequences.assign'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'orders.manage' then 'orders.manage'
    when 'orders.prepare' then 'orders.prepare'
    when 'orders.read' then 'orders.read'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'passes.checkIn' then 'passes.check_in'
    when 'passes.manage' then 'passes.manage'
    when 'passes.read' then 'passes.read'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'pipelines.manage' then 'pipelines.manage'
    when 'pipelines.read' then 'pipelines.read'
    when 'posts.manage' then 'posts.manage'
    when 'posts.moderate' then 'posts.moderate'
    when 'posts.read' then 'posts.read'
    when 'posts.write' then 'posts.write'
    when 'promotions.manage' then 'promotions.manage'
    when 'promotions.read' then 'promotions.read'
    when 'quotes.manage' then 'quotes.manage'
    when 'quotes.read' then 'quotes.read'
    when 'quotes.write' then 'quotes.write'
    when 'reactions.create' then 'reactions.create'
    when 'reactions.manage' then 'reactions.manage'
    when 'reactions.read' then 'reactions.read'
    when 'relations.manage' then 'relations.manage'
    when 'relations.read' then 'relations.read'
    when 'reminders.manage' then 'reminders.manage'
    when 'reminders.read' then 'reminders.read'
    when 'saved-views.read' then 'views.read'
    when 'saved-views.share' then 'views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.edit' then 'segments.edit'
    when 'segments.read' then 'segments.read'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_principals.manage'
    when 'service-accounts.read' then 'service_principals.read'
    when 'settings.platform' then 'settings.manage'
    when 'settings.read' then 'settings.read'
    when 'settings.update' then 'settings.update'
    when 'share-links.create' then 'share_links.create'
    when 'share-links.read' then 'share_links.read'
    when 'shipments.manage' then 'shipments.manage'
    when 'shipments.read' then 'shipments.read'
    when 'signatures.manage' then 'signatures.manage'
    when 'signatures.read' then 'signatures.read'
    when 'signatures.request' then 'signatures.request'
    when 'sla.manage' then 'sla.manage'
    when 'sla.read' then 'sla.read'
    when 'sso.manage' then 'sso.manage'
    when 'tags.apply' then 'tags.apply'
    when 'tags.manage' then 'tags.manage'
    when 'tags.read' then 'tags.read'
    when 'tasks.manage' then 'work_items.manage'
    when 'tasks.read' then 'work_items.read'
    when 'tasks.write' then 'work_items.write'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'time-tracking.approve' then 'time_tracking.approve'
    when 'time-tracking.manage' then 'time_tracking.manage'
    when 'time-tracking.read' then 'time_tracking.read'
    when 'time-tracking.track' then 'time_tracking.track'
    when 'timeline.read' then 'activity.read'
    when 'trash.create' then 'trash.create'
    when 'trash.manage' then 'trash.manage'
    when 'trash.read' then 'trash.read'
    when 'trash.restore' then 'trash.restore'
    when 'usage.read' then 'usage.read'
    when 'usage.record' then 'usage.record'
    when 'versions.create' then 'versions.create'
    when 'versions.manage' then 'versions.manage'
    when 'versions.read' then 'versions.read'
    when 'versions.restore' then 'versions.restore'
    when 'waitlist.invite' then 'members.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'webhooks-out.manage' then 'webhooks.manage'
    when 'webhooks-out.view' then 'webhooks.read'
    when 'workflow-editor.admin' then 'workflow.admin'
    when 'workflow-editor.edit' then 'workflow.edit'
    when 'workflow-editor.publish' then 'workflow.publish'
    when 'workflow-editor.read' then 'workflow.read'
    when 'workflow-editor.run' then 'workflow.run'
    when 'workflows.admin' then 'workflow.admin'
    when 'workflows.read' then 'workflow.read'
    when 'workflows.run' then 'workflow.run'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_permission_override (
  tenant     uuid,
  role       text,
  permission text,
  granted    boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_role uuid;
  v_permission uuid;
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (v_service or coalesce(better_supabase.member_can(auth.uid(), tenant, 'roles.manage'), false)) then
    raise exception 'Not allowed to change role permissions' using errcode = '42501', hint = 'PERMISSIONS_FORBIDDEN';
  end if;
  select r."id" into v_role from "better_supabase"."roles" r
  where (r."id"::text = role or r."key" = role) and r."scope"::text = 'tenant';
  if v_role is null then
    raise exception 'Unknown role' using errcode = 'P0002', hint = 'PERMISSIONS_ROLE_UNKNOWN';
  end if;
  select p."id" into v_permission from "better_supabase"."permissions" p where p."key" = permission;
  if v_permission is null then
    raise exception 'Unknown permission' using errcode = 'P0002', hint = 'PERMISSIONS_KEY_UNKNOWN';
  end if;
  if not v_service then
    if not better_supabase.can_assign(tenant, v_role::text) then
      raise exception 'That role is above your own' using errcode = '42501', hint = 'PERMISSIONS_ROLE_CEILING';
    end if;
    if not coalesce(better_supabase.member_can(auth.uid(), tenant, permission), false) then
      raise exception 'You can only change keys you hold' using errcode = '42501', hint = 'PERMISSIONS_KEY_CEILING';
    end if;
    if granted is distinct from true and permission = 'roles.manage' and exists (
      select 1 from "public"."memberships" mm where mm."organization_id" = tenant and mm."user_id" = auth.uid() and mm."role" = v_role
    ) then
      raise exception 'You cannot take this key from your own role' using errcode = '42501', hint = 'PERMISSIONS_SELF_LOCKOUT';
    end if;
  end if;
  if granted is null then
    delete from "better_supabase"."permission_overrides" ov
    where ov."organization_id" = tenant and ov."role_id" = v_role and ov."permission_id" = v_permission;
  else
    insert into "better_supabase"."permission_overrides" ("organization_id", "role_id", "permission_id", "granted")
    values (tenant, v_role, v_permission, granted)
    on conflict ("organization_id", "role_id", "permission_id") do update set "granted" = excluded."granted";
  end if;
  return (select jsonb_build_object(
      'id', r."id",
      'key', r."key",
      'members', (select count(*) from "public"."memberships" mm where mm."organization_id" = set_permission_override.tenant and mm."role" = r."id"),
      'default_permissions', coalesce((
        select jsonb_agg(p."key" order by p."key")
        from "better_supabase"."role_permissions" x join "better_supabase"."permissions" p on p."id" = x."permission_id"
        where x."role_id" = r."id"
      ), '[]'::jsonb),
      'permissions', coalesce((
        select jsonb_agg(p."key" order by p."key")
        from "better_supabase"."permissions" p
        where coalesce(
          (select bool_and(ov."granted") from "better_supabase"."permission_overrides" ov
            where ov."organization_id" = set_permission_override.tenant and ov."role_id" = r."id" and ov."permission_id" = p."id"),
          exists (select 1 from "better_supabase"."role_permissions" x where x."role_id" = r."id" and x."permission_id" = p."id")
        )
      ), '[]'::jsonb),
      'overrides', coalesce((
        select jsonb_agg(jsonb_build_object('permission', p."key", 'granted', ov."granted") order by p."key")
        from "better_supabase"."permission_overrides" ov join "better_supabase"."permissions" p on p."id" = ov."permission_id"
        where ov."organization_id" = set_permission_override.tenant and ov."role_id" = r."id"
      ), '[]'::jsonb)
    ) from "better_supabase"."roles" r where r."id" = v_role);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."list_roles"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_roles"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_permission_override"(uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_permission_override"(uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_roles"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_roles"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_permission_override"(uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_permission_override"(uuid, text, text, boolean) TO "authenticated", "service_role";
