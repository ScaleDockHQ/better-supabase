-- better-supabase module: permissions
-- @bsb-block permissions@1 managed
-- @bsb-hash sha256:386e3454b0cb61ad9405996e8624228b92d365530f29d66ac3688be81e9424aa
-- can(), tenant_ids_with() and is_platform(): one permission contract for policies and SQL modules, over a roles list, a role and permission catalog, an authorization provider or the app's own functions (blocks.permissions.model).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."permission_overrides";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."permission_overrides";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."permission_overrides";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."permission_overrides";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."permission_overrides";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
grant usage on schema better_supabase to supabase_auth_admin;

-- Disabled tenants and users get no permissions and no membership claims
-- (blocks.permissions.disabled; with the managed organizations module, its
-- disabled_at and deleted_at columns).
create or replace function better_supabase.tenant_disabled(tenant uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false
$$;

create or replace function better_supabase.user_disabled(user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false
$$;

revoke execute on function better_supabase.tenant_disabled(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.user_disabled(uuid) from public, anon, authenticated;
grant execute on function better_supabase.tenant_disabled(uuid) to service_role, supabase_auth_admin;
grant execute on function better_supabase.user_disabled(uuid) to service_role, supabase_auth_admin;

-- `*` grants every key and `prefix.*` every key under prefix.
create or replace function better_supabase.permission_matches(granted text, wanted text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select granted = '*' or granted = wanted
    or (right(granted, 2) = '.*' and starts_with(wanted, left(granted, -1)))
$$;

-- The permission keys an OAuth scope grants a delegated token
-- (authorization.delegation.scopes, blocks.permissions.scopes). A scope
-- without an entry grants the key with its own name.
create or replace function better_supabase.scope_permissions(scope text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[scope]
$$;

-- False when the token is narrower than the permission: a permission cap
-- (bsb_permission_cap) without the key, or a delegated token whose scopes
-- don't map to it. True for every other token, the service role included.
-- 0.14 named the cap bs_permission_cap; 0.15 still reads it when the new
-- claim is missing, so a cap from an older runAs keeps narrowing.
create or replace function better_supabase.cap_allows(permission text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when jwt is null then true
    when jsonb_typeof(cap) = 'array'
      and not exists (
        select 1 from jsonb_array_elements_text(cap) c(key)
        where better_supabase.permission_matches(c.key, cap_allows.permission)
      ) then false
    when coalesce(jwt ->> 'client_id', '') = ''
      and (jwt -> 'act' is null
        or (jsonb_typeof(jwt -> 'act') = 'object'
          and jwt -> 'act' ->> 'kind' in ('support', 'impersonation'))) then true
    else exists (
      select 1
      from unnest(case jsonb_typeof(jwt -> 'scope')
          when 'string' then regexp_split_to_array(btrim(jwt ->> 'scope'), '\s+')
          when 'array' then array(select jsonb_array_elements_text(jwt -> 'scope'))
          else '{}'::text[]
        end) s(scope)
      cross join lateral unnest(better_supabase.scope_permissions(s.scope)) k(key)
      where s.scope <> ''
        and better_supabase.permission_matches(k.key, cap_allows.permission)
    )
  end
  from (select auth.jwt() as jwt) as token
  cross join lateral (
    select coalesce(jwt -> 'bsb_permission_cap', jwt -> 'bs_permission_cap') as cap
  ) as capped
$$;

-- The permission key an operation (<module>.<action>, or a name in
-- authorization.operations) checks, after renames and the provider's table.
-- Null for an operation nobody declared, which callers refuse.
create or replace function better_supabase.operation_permission(op text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case op
    when 'access-requests.create' then 'access_requests.create'
    when 'access-requests.emergency' then 'access_requests.emergency'
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'access-requests.review' then 'access_requests.review'
    when 'accounting.close' then 'accounting.close'
    when 'accounting.manage' then 'accounting.manage'
    when 'accounting.post' then 'accounting.post'
    when 'accounting.read' then 'accounting.read'
    when 'accounting.write' then 'accounting.write'
    when 'acknowledgements.acknowledge' then 'acknowledgements.acknowledge'
    when 'acknowledgements.manage' then 'acknowledgements.manage'
    when 'acknowledgements.read' then 'acknowledgements.read'
    when 'activities.manage' then 'activities.manage'
    when 'activities.read' then 'activities.read'
    when 'activities.readRestricted' then 'activities.read_restricted'
    when 'activities.write' then 'activities.write'
    when 'agents.create' then 'agents.write'
    when 'agents.moderate' then 'agents.moderate'
    when 'agents.publish' then 'agents.publish'
    when 'agents.read' then 'agents.read'
    when 'ai-chat.admin' then 'ai_chat.manage'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai_files.manage'
    when 'ai-files.upload' then 'ai_files.upload'
    when 'ai-keys.manage' then 'ai_keys.manage'
    when 'ai-keys.use' then 'ai_keys.use'
    when 'ai-schedules.create' then 'ai_schedules.write'
    when 'ai-schedules.manage' then 'ai_schedules.manage'
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
    when 'automations.admin' then 'automations.manage'
    when 'automations.edit' then 'automations.write'
    when 'automations.publish' then 'automations.publish'
    when 'automations.read' then 'automations.read'
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
    when 'care-plans.evaluate' then 'care_plans.evaluate'
    when 'care-plans.manage' then 'care_plans.manage'
    when 'care-plans.publish' then 'care_plans.publish'
    when 'care-plans.read' then 'care_plans.read'
    when 'care-plans.write' then 'care_plans.write'
    when 'cases.close' then 'cases.close'
    when 'cases.create' then 'cases.create'
    when 'cases.manage' then 'cases.manage'
    when 'cases.read' then 'cases.read'
    when 'cases.write' then 'cases.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'compliance.collect' then 'compliance.collect'
    when 'compliance.manage' then 'compliance.manage'
    when 'compliance.read' then 'compliance.read'
    when 'connectors.manage' then 'connectors.manage'
    when 'connectors.read' then 'connectors.read'
    when 'connectors.use' then 'connectors.use'
    when 'consents.manage' then 'consents.manage'
    when 'consents.read' then 'consents.read'
    when 'consents.record' then 'consents.record'
    when 'contacts.approveSupplier' then 'contacts.approve_supplier'
    when 'contacts.manage' then 'contacts.manage'
    when 'contacts.read' then 'contacts.read'
    when 'contacts.write' then 'contacts.write'
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
    when 'custom-fields.sensitive' then 'custom_fields.read_sensitive'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'data_lifecycle.export'
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
    when 'employees.viewSensitive' then 'employees.read_sensitive'
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
    when 'field-history.read' then 'field_history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'goals.manage' then 'goals.manage'
    when 'goals.read' then 'goals.read'
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
    when 'inspections.manage' then 'inspections.manage'
    when 'inspections.read' then 'inspections.read'
    when 'inspections.write' then 'inspections.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invitations.view' then 'members.invite'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.overrideMatch' then 'invoices.override_match'
    when 'invoices.purchase' then 'invoices.purchase'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'knowledge.manage'
    when 'knowledge.read' then 'knowledge.read'
    when 'knowledge.write' then 'knowledge.write'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'mail-sync.connect' then 'mail_sync.connect'
    when 'mail-sync.manage' then 'mail_sync.manage'
    when 'mail-sync.read' then 'mail_sync.read'
    when 'mail-sync.send' then 'mail_sync.send'
    when 'manufacturing.manage' then 'manufacturing.manage'
    when 'manufacturing.produce' then 'manufacturing.produce'
    when 'manufacturing.read' then 'manufacturing.read'
    when 'manufacturing.write' then 'manufacturing.write'
    when 'medications.administer' then 'medications.administer'
    when 'medications.manage' then 'medications.manage'
    when 'medications.prescribe' then 'medications.prescribe'
    when 'medications.read' then 'medications.read'
    when 'memory.manage' then 'memory.manage'
    when 'memory.read' then 'memory.read'
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
    when 'numbering.assign' then 'numbering.assign'
    when 'observations.manage' then 'observations.manage'
    when 'observations.read' then 'observations.read'
    when 'observations.record' then 'observations.record'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'orders.manage' then 'orders.manage'
    when 'orders.overrideCredit' then 'orders.override_credit'
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
    when 'qualifications.grant' then 'qualifications.grant'
    when 'qualifications.manage' then 'qualifications.manage'
    when 'qualifications.read' then 'qualifications.read'
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
    when 'risks.assess' then 'risks.assess'
    when 'risks.manage' then 'risks.manage'
    when 'risks.read' then 'risks.read'
    when 'risks.write' then 'risks.write'
    when 'saved-views.read' then 'saved_views.read'
    when 'saved-views.share' then 'saved_views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.edit' then 'segments.write'
    when 'segments.read' then 'segments.read'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_accounts.manage'
    when 'service-accounts.read' then 'service_accounts.read'
    when 'settings.platform' then 'settings.manage'
    when 'settings.read' then 'settings.read'
    when 'settings.update' then 'settings.update'
    when 'share-links.create' then 'share_links.create'
    when 'share-links.read' then 'share_links.read'
    when 'shifts.manage' then 'shifts.manage'
    when 'shifts.read' then 'shifts.read'
    when 'shifts.request' then 'shifts.request'
    when 'shifts.write' then 'shifts.write'
    when 'shipments.manage' then 'shipments.manage'
    when 'shipments.read' then 'shipments.read'
    when 'signatures.manage' then 'signatures.manage'
    when 'signatures.read' then 'signatures.read'
    when 'signatures.request' then 'signatures.request'
    when 'sla.manage' then 'sla.manage'
    when 'sla.read' then 'sla.read'
    when 'sso.manage' then 'sso.manage'
    when 'subjects.manage' then 'subjects.manage'
    when 'tags.apply' then 'tags.apply'
    when 'tags.manage' then 'tags.manage'
    when 'tags.read' then 'tags.read'
    when 'tasks.manage' then 'tasks.manage'
    when 'tasks.read' then 'tasks.read'
    when 'tasks.write' then 'tasks.write'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'time-tracking.approve' then 'time_tracking.approve'
    when 'time-tracking.manage' then 'time_tracking.manage'
    when 'time-tracking.read' then 'time_tracking.read'
    when 'time-tracking.track' then 'time_tracking.track'
    when 'timeline.read' then 'timeline.read'
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
    when 'waitlist.invite' then 'waitlist.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'webhooks-out.manage' then 'webhooks.manage'
    when 'webhooks-out.view' then 'webhooks.read'
    when 'workflow-editor.admin' then 'workflow_editor.manage'
    when 'workflow-editor.edit' then 'workflow_editor.write'
    when 'workflow-editor.publish' then 'workflow_editor.publish'
    when 'workflow-editor.read' then 'workflow_editor.read'
    when 'workflow-editor.run' then 'workflow_editor.run'
    when 'workflows.admin' then 'workflows.manage'
    when 'workflows.read' then 'workflows.read'
    when 'workflows.run' then 'workflows.run'
  end
$$;

create table if not exists "better_supabase"."roles" (
  "id" uuid primary key default gen_random_uuid(),
  "key" text not null unique
);
-- A tenant role goes in memberships, a platform role in platform assignments.
alter table "better_supabase"."roles" add column if not exists "scope" text not null default 'tenant';
do $$
begin
  if coalesce(obj_description((
    select c.oid from pg_catalog.pg_constraint c
    where c.conrelid = '"better_supabase"."roles"'::regclass and c.conname = 'roles_scope_check'
  ), 'pg_constraint'), '') <> 'better-supabase check fb19a0bd' then
    alter table "better_supabase"."roles" drop constraint if exists "roles_scope_check";
    alter table "better_supabase"."roles" add constraint "roles_scope_check" check ("scope" in ('tenant', 'platform'));
    comment on constraint "roles_scope_check" on "better_supabase"."roles" is 'better-supabase check fb19a0bd';
  end if;
end;
$$;
create table if not exists "better_supabase"."permissions" (
  "id" uuid primary key default gen_random_uuid(),
  "key" text not null unique
);
create table if not exists "better_supabase"."role_permissions" (
  "role_id" uuid not null references "better_supabase"."roles" on delete cascade,
  "permission_id" uuid not null references "better_supabase"."permissions" on delete cascade,
  primary key ("role_id", "permission_id")
);
create index if not exists role_permissions_permission_idx on "better_supabase"."role_permissions" ("permission_id");
create table if not exists "better_supabase"."permission_overrides" (
  "organization_id" uuid not null,
  "role_id" uuid not null references "better_supabase"."roles" on delete cascade,
  "permission_id" uuid not null references "better_supabase"."permissions" on delete cascade,
  "granted" boolean not null,
  primary key ("organization_id", "role_id", "permission_id")
);
create index if not exists permission_overrides_role_idx on "better_supabase"."permission_overrides" ("role_id");
create index if not exists permission_overrides_permission_idx on "better_supabase"."permission_overrides" ("permission_id");
create table if not exists "better_supabase"."platform_roles" (
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role_id" uuid not null references "better_supabase"."roles" on delete cascade,
  primary key ("user_id", "role_id")
);
create index if not exists platform_roles_role_idx on "better_supabase"."platform_roles" ("role_id");
do $$
declare
  t text;
begin
  foreach t in array array['"better_supabase"."roles"', '"better_supabase"."permissions"', '"better_supabase"."role_permissions"', '"better_supabase"."permission_overrides"', '"better_supabase"."platform_roles"'] loop
    execute format('alter table %s enable row level security', t);
    execute format('revoke all on %s from public, anon, authenticated', t);
    execute format('grant all on %s to service_role', t);
  end loop;
end;
$$;
-- The catalog is written directly by the service role, so a row trigger
-- audits it.
do $$
begin
  execute format('select better_supabase.audit(%s::regclass, category => %L, tenant_column => %L)', quote_literal('"better_supabase"."roles"'), 'access', null);
  execute format('select better_supabase.audit(%s::regclass, category => %L, tenant_column => %L)', quote_literal('"better_supabase"."permissions"'), 'access', null);
  execute format('select better_supabase.audit(%s::regclass, category => %L, tenant_column => %L)', quote_literal('"better_supabase"."role_permissions"'), 'access', null);
  execute format('select better_supabase.audit(%s::regclass, category => %L, tenant_column => %L)', quote_literal('"better_supabase"."permission_overrides"'), 'access', 'organization_id');
  execute format('select better_supabase.audit(%s::regclass, category => %L, tenant_column => %L)', quote_literal('"better_supabase"."platform_roles"'), 'access', null);
end;
$$;

create or replace function better_supabase.member_can(member uuid, tenant uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select member is not null
    and not better_supabase.user_disabled(member)
    and not better_supabase.tenant_disabled(tenant)
    and (member is distinct from auth.uid() or better_supabase.cap_allows(member_can.permission))
    and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = member_can.tenant and m."user_id" = member_can.member
        and exists (select 1 from "better_supabase"."permissions" p where p."key" = member_can.permission and coalesce(
      (select bool_and(o."granted") from "better_supabase"."permission_overrides" o
        where o."organization_id" = m."organization_id"
          and o."role_id" = m."role"
          and o."permission_id" = p."id"),
      exists (select 1 from "better_supabase"."role_permissions" rp where rp."role_id" = m."role" and rp."permission_id" = p."id")
    ))
    )
$$;


-- member_can without the disabled-tenant check, for the actions a member
-- takes while the tenant waits to be purged, such as cancelling the deletion.

create or replace function better_supabase.member_can_while_deleting(member uuid, tenant uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select member is not null
    and not better_supabase.user_disabled(member)
    and (member is distinct from auth.uid() or better_supabase.cap_allows(member_can_while_deleting.permission))
    and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = member_can_while_deleting.tenant and m."user_id" = member_can_while_deleting.member
        and exists (select 1 from "better_supabase"."permissions" p where p."key" = member_can_while_deleting.permission and coalesce(
      (select bool_and(o."granted") from "better_supabase"."permission_overrides" o
        where o."organization_id" = m."organization_id"
          and o."role_id" = m."role"
          and o."permission_id" = p."id"),
      exists (select 1 from "better_supabase"."role_permissions" rp where rp."role_id" = m."role" and rp."permission_id" = p."id")
    ))
    )
$$;

-- The permission keys a member holds in a tenant.
create or replace function better_supabase.member_permissions(member uuid, tenant uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(p."key" order by p."key"), '{}'::text[])
    from "better_supabase"."permissions" p
    where exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = member_permissions.tenant and m."user_id" = member_permissions.member
        and coalesce(
      (select bool_and(o."granted") from "better_supabase"."permission_overrides" o
        where o."organization_id" = m."organization_id"
          and o."role_id" = m."role"
          and o."permission_id" = p."id"),
      exists (select 1 from "better_supabase"."role_permissions" rp where rp."role_id" = m."role" and rp."permission_id" = p."id")
    )
    )
$$;

create or replace function better_supabase.platform_can(member uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select member is not null
    and (platform_can.member is distinct from auth.uid() or auth.jwt() -> 'act' is null)
    and not better_supabase.user_disabled(member)
    and (member is distinct from auth.uid() or better_supabase.cap_allows(platform_can.permission))
    and (exists (
    select 1
    from "better_supabase"."platform_roles" a
    join "better_supabase"."role_permissions" rp on rp."role_id" = a."role_id"
    join "better_supabase"."permissions" p on p."id" = rp."permission_id"
    where a."user_id" = platform_can.member
      and p."key" = platform_can.permission
  ) or (platform_can.member = auth.uid() and exists (
    select 1
    from jsonb_array_elements_text(
      case when jsonb_typeof(coalesce(auth.jwt() -> 'platform_permissions', auth.jwt() -> 'app_metadata' -> 'platform_permissions')) = 'array'
        then coalesce(auth.jwt() -> 'platform_permissions', auth.jwt() -> 'app_metadata' -> 'platform_permissions')
        else '[]'::jsonb end
    ) g(key)
    where better_supabase.permission_matches(g.key, platform_can.permission)
  )))
$$;

create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select m."organization_id"
  from "public"."memberships" m
  where m."user_id" = (select auth.uid())
    and not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(m."organization_id")
    and better_supabase.cap_allows(tenant_ids_with.permission)
    and exists (select 1 from "better_supabase"."permissions" p where p."key" = tenant_ids_with.permission and coalesce(
      (select bool_and(o."granted") from "better_supabase"."permission_overrides" o
        where o."organization_id" = m."organization_id"
          and o."role_id" = m."role"
          and o."permission_id" = p."id"),
      exists (select 1 from "better_supabase"."role_permissions" rp where rp."role_id" = m."role" and rp."permission_id" = p."id")
    ))
$$;

-- Members assign roles up to their own permissions: every key the role
-- grants must be one the member holds in the tenant.
create or replace function better_supabase.can_assign_as(member uuid, tenant uuid, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select member is not null
    and exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = can_assign_as.tenant and m."user_id" = can_assign_as.member
    )
      and exists (
        select 1 from "better_supabase"."roles" r
        where r."id"::text = can_assign_as.role and r."scope"::text = 'tenant'
      )
    and not exists (
      select 1
        from (
          select r."id" as "role", can_assign_as.tenant as "organization_id"
          from "better_supabase"."roles" r
          where r."id"::text = can_assign_as.role
        ) m
        cross join "better_supabase"."permissions" p
        cross join lateral (select p."key" as key) k
        where coalesce(
      (select bool_and(o."granted") from "better_supabase"."permission_overrides" o
        where o."organization_id" = m."organization_id"
          and o."role_id" = m."role"
          and o."permission_id" = p."id"),
      exists (select 1 from "better_supabase"."role_permissions" rp where rp."role_id" = m."role" and rp."permission_id" = p."id")
    )
        and not coalesce(better_supabase.member_can(can_assign_as.member, can_assign_as.tenant, k.key), false)
    )
$$;

create or replace function better_supabase.can_assign(tenant uuid, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role' or better_supabase.can_assign_as(auth.uid(), can_assign.tenant, can_assign.role)
$$;

-- A platform role is assignable by a member who holds every key it grants.
create or replace function better_supabase.platform_can_assign(member uuid, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select member is not null
    and exists (
      select 1 from "better_supabase"."roles" r
      where r."id"::text = platform_can_assign.role and r."scope"::text = 'platform'
    )
    and not exists (
      select 1
      from "better_supabase"."role_permissions" rp
      join "better_supabase"."permissions" p on p."id" = rp."permission_id"
      where rp."role_id"::text = platform_can_assign.role
        and not coalesce(better_supabase.platform_can(platform_can_assign.member, p."key"), false)
    )
$$;
revoke execute on function better_supabase.platform_can_assign(uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.platform_can_assign(uuid, text) to service_role;

create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(m."organization_id"::text, to_jsonb(better_supabase.member_permissions(m."user_id", m."organization_id"))), '{}'::jsonb)
  from "public"."memberships" m
  where m."user_id" = permission_claims.user_id
    and not better_supabase.user_disabled(permission_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id")
$$;

-- The access contract. Policies and SQL modules call these, never a model's
-- tables, so the model can change without touching them. In a policy, use
-- the set, which runs once per statement and can use the tenant index:
--   using (organization_id in (select better_supabase.tenant_ids_with('invoices.read')))
-- can() with a column argument runs once per row, even inside (select ...);
-- keep it for checks on one row and inside functions.
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when can.scope = 'platform' then coalesce(better_supabase.platform_can(auth.uid(), can.permission), false)
    when can.scope in ('organization', 'tenant') then coalesce(better_supabase.member_can(auth.uid(), can.scope_id, can.permission), false)
    else false
  end
$$;

-- The same question for another user, for checks such as an inviter's
-- authority at accept time. Null when the model can't answer for others.
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when can_user.scope = 'platform' then better_supabase.platform_can(can_user.member, can_user.permission)
    when can_user.scope in ('organization', 'tenant') then better_supabase.member_can(can_user.member, can_user.scope_id, can_user.permission)
    else false
  end
$$;

create or replace function better_supabase.is_platform(permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(better_supabase.platform_can(auth.uid(), is_platform.permission), false)
$$;

-- { [tenant]: permission keys } for one tenant, the active one; {} without a
-- tenant or when the model can't answer.
create or replace function better_supabase.permission_claims(user_id uuid, tenant uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when permission_claims.tenant is null then '{}'::jsonb
    else coalesce(jsonb_strip_nulls(jsonb_build_object(permission_claims.tenant::text, to_jsonb(better_supabase.member_permissions(permission_claims.user_id, permission_claims.tenant)))), '{}'::jsonb)
  end
$$;

-- The caller's permission keys in a tenant, for client checks. With keys,
-- the ones can() grants: every model answers, including a provider and
-- delegated tokens. Without them, the keys the model lists for the member,
-- wildcards as granted (the custom model lists none).
create or replace function better_supabase.my_permissions(tenant uuid, keys text[] default null)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when auth.uid() is null or my_permissions.tenant is null then '{}'::text[]
    when my_permissions.keys is not null then coalesce((
      select array_agg(distinct k order by k)
      from unnest(my_permissions.keys) as k
      where better_supabase.can('tenant', my_permissions.tenant, k)
    ), '{}'::text[])
    when better_supabase.tenant_disabled(my_permissions.tenant) then '{}'::text[]
    else coalesce((
      select array_agg(distinct p order by p)
      from unnest(better_supabase.member_permissions(auth.uid(), my_permissions.tenant)) as p
      where better_supabase.cap_allows(p)
    ), '{}'::text[])
  end
$$;
-- The tenant roles of the catalog with their keys in one tenant: the role's
-- defaults, the keys after this tenant's overrides, the overrides and how many
-- members hold the role.
create or replace function "better_supabase"."list_roles"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."list_roles"(uuid) from public, anon;
grant execute on function "better_supabase"."list_roles"(uuid) to authenticated, service_role;

-- Grants (true) or denies (false) one key to a role in one tenant; null
-- clears the override, so the role's default applies again. Members change
-- only roles they could assign, and only keys they hold themselves.
-- Errors carry a code in the hint: PERMISSIONS_FORBIDDEN, PERMISSIONS_ROLE_UNKNOWN,
-- PERMISSIONS_KEY_UNKNOWN, PERMISSIONS_ROLE_CEILING, PERMISSIONS_KEY_CEILING,
-- PERMISSIONS_SELF_LOCKOUT.
create or replace function "better_supabase"."set_permission_override"(tenant uuid, role text, permission text, granted boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."set_permission_override"(uuid, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_permission_override"(uuid, text, text, boolean) to authenticated, service_role;

revoke execute on function better_supabase.permission_matches(text, text) from public;
grant execute on function better_supabase.permission_matches(text, text) to anon, authenticated, service_role;
revoke execute on function better_supabase.scope_permissions(text) from public;
grant execute on function better_supabase.scope_permissions(text) to anon, authenticated, service_role;
revoke execute on function better_supabase.cap_allows(text) from public;
grant execute on function better_supabase.cap_allows(text) to anon, authenticated, service_role;
revoke execute on function better_supabase.operation_permission(text) from public;
grant execute on function better_supabase.operation_permission(text) to anon, authenticated, service_role;
revoke execute on function better_supabase.can(text, uuid, text) from public;
grant execute on function better_supabase.can(text, uuid, text) to anon, authenticated, service_role;
revoke execute on function better_supabase.tenant_ids_with(text) from public;
grant execute on function better_supabase.tenant_ids_with(text) to anon, authenticated, service_role;
revoke execute on function better_supabase.is_platform(text) from public;
grant execute on function better_supabase.is_platform(text) to anon, authenticated, service_role;
revoke execute on function better_supabase.can_assign(uuid, text) from public;
grant execute on function better_supabase.can_assign(uuid, text) to anon, authenticated, service_role;
revoke execute on function better_supabase.my_permissions(uuid, text[]) from public;
grant execute on function better_supabase.my_permissions(uuid, text[]) to anon, authenticated, service_role;
revoke execute on function better_supabase.member_can(uuid, uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.member_can(uuid, uuid, text) to service_role, supabase_auth_admin;
revoke execute on function better_supabase.member_can_while_deleting(uuid, uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.member_can_while_deleting(uuid, uuid, text) to service_role, supabase_auth_admin;
revoke execute on function better_supabase.member_permissions(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_permissions(uuid, uuid) to service_role, supabase_auth_admin;
revoke execute on function better_supabase.platform_can(uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.platform_can(uuid, text) to service_role, supabase_auth_admin;
revoke execute on function better_supabase.can_user(uuid, text, uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.can_user(uuid, text, uuid, text) to service_role, supabase_auth_admin;
revoke execute on function better_supabase.permission_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.permission_claims(uuid) to service_role, supabase_auth_admin;
revoke execute on function better_supabase.permission_claims(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.permission_claims(uuid, uuid) to service_role, supabase_auth_admin;
revoke execute on function better_supabase.can_assign_as(uuid, uuid, text) from public, anon, authenticated;
grant execute on function better_supabase.can_assign_as(uuid, uuid, text) to service_role, supabase_auth_admin;

-- The permission claim: { [tenant id]: permission keys }, for the access
-- token hook when the app checks permissions from the token. Write the
-- active tenant only, and mark the claim truncated when it outgrows the
-- token budget, so readers ask the database instead:
--   declare
--     tenant text := event #>> '{claims,app_metadata,tenant_id}';
--     keys jsonb := better_supabase.permission_claims((event ->> 'user_id')::uuid, tenant::uuid);
--   begin
--     if octet_length(keys::text) > 2048 then
--       event := jsonb_set(event, '{claims,permissions_truncated}', 'true');
--       keys := '{}'::jsonb;
--     end if;
--     return jsonb_set(event, '{claims,permissions}', keys);

-- blocks.permissions.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."tenant_disabled"(tenant uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."tenant_disabled"($1) $$;
revoke execute on function "api"."tenant_disabled"(uuid) from public, anon, authenticated;
grant execute on function "api"."tenant_disabled"(uuid) to service_role;

create or replace function "api"."user_disabled"(user_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."user_disabled"($1) $$;
revoke execute on function "api"."user_disabled"(uuid) from public, anon, authenticated;
grant execute on function "api"."user_disabled"(uuid) to service_role;

create or replace function "api"."platform_can_assign"(member uuid, role text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."platform_can_assign"($1, $2) $$;
revoke execute on function "api"."platform_can_assign"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."platform_can_assign"(uuid, text) to service_role;

create or replace function "api"."list_roles"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_roles"($1) $$;
revoke execute on function "api"."list_roles"(uuid) from public, anon;
grant execute on function "api"."list_roles"(uuid) to authenticated, service_role;

create or replace function "api"."set_permission_override"(tenant uuid, role text, permission text, granted boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_permission_override"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_permission_override"(uuid, text, text, boolean) from public, anon;
grant execute on function "api"."set_permission_override"(uuid, text, text, boolean) to authenticated, service_role;

create or replace function "api"."permission_matches"(granted text, wanted text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."permission_matches"($1, $2) $$;
revoke execute on function "api"."permission_matches"(text, text) from public;
grant execute on function "api"."permission_matches"(text, text) to anon, authenticated, service_role;

create or replace function "api"."scope_permissions"(scope text)
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."scope_permissions"($1) $$;
revoke execute on function "api"."scope_permissions"(text) from public;
grant execute on function "api"."scope_permissions"(text) to anon, authenticated, service_role;

create or replace function "api"."cap_allows"(permission text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cap_allows"($1) $$;
revoke execute on function "api"."cap_allows"(text) from public;
grant execute on function "api"."cap_allows"(text) to anon, authenticated, service_role;

create or replace function "api"."operation_permission"(op text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."operation_permission"($1) $$;
revoke execute on function "api"."operation_permission"(text) from public;
grant execute on function "api"."operation_permission"(text) to anon, authenticated, service_role;

create or replace function "api"."can"(scope text, scope_id uuid, permission text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."can"($1, $2, $3) $$;
revoke execute on function "api"."can"(text, uuid, text) from public;
grant execute on function "api"."can"(text, uuid, text) to anon, authenticated, service_role;

create or replace function "api"."tenant_ids_with"(permission text)
returns setof uuid
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."tenant_ids_with"($1) $$;
revoke execute on function "api"."tenant_ids_with"(text) from public;
grant execute on function "api"."tenant_ids_with"(text) to anon, authenticated, service_role;

create or replace function "api"."is_platform"(permission text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."is_platform"($1) $$;
revoke execute on function "api"."is_platform"(text) from public;
grant execute on function "api"."is_platform"(text) to anon, authenticated, service_role;

create or replace function "api"."can_assign"(tenant uuid, role text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."can_assign"($1, $2) $$;
revoke execute on function "api"."can_assign"(uuid, text) from public;
grant execute on function "api"."can_assign"(uuid, text) to anon, authenticated, service_role;

create or replace function "api"."my_permissions"(tenant uuid, keys text[] default null)
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."my_permissions"($1, $2) $$;
revoke execute on function "api"."my_permissions"(uuid, text[]) from public;
grant execute on function "api"."my_permissions"(uuid, text[]) to anon, authenticated, service_role;

create or replace function "api"."member_can"(member uuid, tenant uuid, permission text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."member_can"($1, $2, $3) $$;
revoke execute on function "api"."member_can"(uuid, uuid, text) from public, anon, authenticated;
grant execute on function "api"."member_can"(uuid, uuid, text) to service_role;

create or replace function "api"."member_can_while_deleting"(member uuid, tenant uuid, permission text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."member_can_while_deleting"($1, $2, $3) $$;
revoke execute on function "api"."member_can_while_deleting"(uuid, uuid, text) from public, anon, authenticated;
grant execute on function "api"."member_can_while_deleting"(uuid, uuid, text) to service_role;

create or replace function "api"."member_permissions"(member uuid, tenant uuid)
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."member_permissions"($1, $2) $$;
revoke execute on function "api"."member_permissions"(uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."member_permissions"(uuid, uuid) to service_role;

create or replace function "api"."platform_can"(member uuid, permission text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."platform_can"($1, $2) $$;
revoke execute on function "api"."platform_can"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."platform_can"(uuid, text) to service_role;

create or replace function "api"."can_user"(member uuid, scope text, scope_id uuid, permission text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."can_user"($1, $2, $3, $4) $$;
revoke execute on function "api"."can_user"(uuid, text, uuid, text) from public, anon, authenticated;
grant execute on function "api"."can_user"(uuid, text, uuid, text) to service_role;

create or replace function "api"."permission_claims"(user_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."permission_claims"($1) $$;
revoke execute on function "api"."permission_claims"(uuid) from public, anon, authenticated;
grant execute on function "api"."permission_claims"(uuid) to service_role;

create or replace function "api"."permission_claims"(user_id uuid, tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."permission_claims"($1, $2) $$;
revoke execute on function "api"."permission_claims"(uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."permission_claims"(uuid, uuid) to service_role;

create or replace function "api"."can_assign_as"(member uuid, tenant uuid, role text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."can_assign_as"($1, $2, $3) $$;
revoke execute on function "api"."can_assign_as"(uuid, uuid, text) from public, anon, authenticated;
grant execute on function "api"."can_assign_as"(uuid, uuid, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
