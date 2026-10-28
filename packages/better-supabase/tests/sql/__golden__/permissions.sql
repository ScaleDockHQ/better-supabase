-- ==== alone: schema supabase/schemas/900_better_supabase_019_permissions.sql
-- better-supabase module: permissions
-- @bsb-block permissions@1 managed
-- @bsb-hash sha256:40e9199a4240b87a025c7da3485a4e0a058116da411699fbe842ecdc6cc63a59
-- can(), tenant_ids_with() and is_platform(): one permission contract for policies and SQL modules, over a roles list, a role and permission catalog, an authorization provider or the app's own functions (blocks.permissions.model).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
  end
$$;

-- The roles model (blocks.permissions.roles): each role's permission keys.
create or replace function better_supabase.role_permissions(role text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case role
    when 'owner' then array['*']::text[]
    when 'admin' then array['organization.read', 'organization.update', 'members.*', 'audit.read', 'audit.revert', 'webhooks.*', 'notifications.*', 'billing.*', 'api_keys.*', 'settings.*', 'usage.*', 'timeline.read', 'attachments.*', 'data_lifecycle.*', 'incoming_webhooks.*', 'onboarding.*', 'inbox.*', 'ai_chat.*', 'ai_files.*', 'knowledge.*', 'memory.*', 'agents.*', 'connectors.*', 'ai_schedules.*', 'ai_keys.*', 'tags.*', 'teams.*', 'custom_fields.*', 'share_links.*', 'reminders.*', 'imports.*', 'saved_views.*', 'relations.*', 'bulk.*', 'search.*', 'metrics.*', 'calendar.*', 'bookings.*', 'versions.*', 'trash.*', 'reactions.*', 'approvals.*', 'access_requests.*', 'documents.*', 'drive.*', 'forms.*', 'signatures.*', 'templates.*', 'time_tracking.*', 'service_accounts.*', 'pipelines.*', 'contacts.*', 'activities.*', 'deals.*', 'tasks.*', 'quotes.*', 'invoices.*', 'sla.*', 'goals.*', 'hiring.*', 'employees.*', 'collections.*', 'messages.*', 'channels.*', 'mail_sync.*', 'segments.*', 'assignment.*', 'enrichment.*', 'forecasts.*', 'field_history.*', 'domains.*', 'automations.*', 'reviews.*', 'leave.*', 'ledger.*', 'assets.*', 'scores.*', 'moderation.*', 'enrollments.*', 'guests.*', 'passes.*', 'billable_time.*', 'leases.*', 'expenses.*', 'donations.*', 'dispatch.*', 'shipments.*', 'contracts.*', 'compliance.*', 'acknowledgements.*', 'cases.*', 'incidents.*', 'courses.*', 'sequences.*', 'posts.*', 'content.*']::text[]
    when 'member' then array['organization.read', 'members.read', 'notifications.read', 'api_keys.own', 'settings.read', 'timeline.read', 'attachments.read', 'attachments.upload', 'onboarding.read', 'inbox.read', 'inbox.reply', 'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_files.read', 'ai_files.upload', 'knowledge.read', 'memory.read', 'agents.read', 'agents.create', 'agents.publish', 'connectors.read', 'connectors.use', 'ai_schedules.create', 'custom_fields.read', 'teams.read', 'tags.read', 'tags.apply', 'share_links.read', 'reminders.read', 'saved_views.read', 'relations.read', 'bulk.run', 'search.read', 'metrics.read', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'versions.restore', 'trash.read', 'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read', 'approvals.request', 'access_requests.create', 'documents.read', 'documents.write', 'documents.suggest', 'drive.read', 'drive.create', 'forms.read', 'forms.submit', 'signatures.read', 'signatures.request', 'templates.read', 'templates.apply', 'time_tracking.track', 'leave.request', 'pipelines.read', 'contacts.read', 'contacts.write', 'activities.read', 'activities.write', 'deals.read', 'deals.write', 'tasks.read', 'tasks.write', 'quotes.read', 'quotes.write', 'invoices.read', 'sla.read', 'goals.read', 'employees.read', 'collections.read', 'collections.write', 'domains.read', 'automations.read', 'assets.read', 'scores.read', 'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit', 'dispatch.read', 'dispatch.work', 'shipments.read', 'contracts.read', 'contracts.write', 'compliance.read', 'compliance.collect', 'compliance.acknowledge', 'acknowledgements.acknowledge', 'cases.read', 'cases.create', 'incidents.read', 'incidents.write', 'courses.read', 'sequences.read', 'sequences.enroll', 'posts.read', 'posts.write', 'content.read', 'content.write', 'messages.read', 'messages.send', 'channels.create', 'mail_sync.read', 'mail_sync.connect', 'mail_sync.send', 'segments.read', 'assignment.read', 'enrichment.read', 'forecasts.read', 'field_history.read']::text[]
    when 'viewer' then array['organization.read']::text[]
    else '{}'::text[]
  end
$$;

create or replace function better_supabase.role_grants(role text, permission text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select exists (
    select 1 from unnest(better_supabase.role_permissions(role)) g(key)
    where better_supabase.permission_matches(g.key, permission)
  )
$$;
revoke execute on function better_supabase.role_permissions(text) from public, anon, authenticated;
revoke execute on function better_supabase.role_grants(text, text) from public, anon, authenticated;
grant execute on function better_supabase.role_permissions(text) to service_role, supabase_auth_admin;
grant execute on function better_supabase.role_grants(text, text) to service_role, supabase_auth_admin;

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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = member_can.tenant and m."user_id" = member_can.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can.permission)
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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = member_can_while_deleting.tenant and m."user_id" = member_can_while_deleting.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can_while_deleting.permission)
    )
$$;

-- The permission keys a member holds in a tenant (wildcards as configured).
create or replace function better_supabase.member_permissions(member uuid, tenant uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
      select better_supabase.role_permissions(m."role") from "better_supabase"."memberships" m
      where m."organization_id" = member_permissions.tenant and m."user_id" = member_permissions.member and m."disabled_at" is null
    ), '{}'::text[])
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
    and ((platform_can.member = auth.uid() and exists (
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
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
    and better_supabase.cap_allows(tenant_ids_with.permission)
    and better_supabase.role_grants(m."role", tenant_ids_with.permission)
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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = can_assign_as.tenant and m."user_id" = can_assign_as.member and m."disabled_at" is null
    )
    and not exists (
      select 1 from unnest(better_supabase.role_permissions(can_assign_as.role)) k(key) where true
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


create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(m."organization_id"::text, to_jsonb(better_supabase.member_permissions(m."user_id", m."organization_id"))), '{}'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = permission_claims.user_id
    and not better_supabase.user_disabled(permission_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
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
drop function if exists "better_supabase"."list_roles"(uuid);
drop function if exists "better_supabase"."set_permission_override"(uuid, text, text, boolean);

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_019_permissions.sql
-- better-supabase module: permissions
-- @bsb-block-data permissions
-- @bsb-hash sha256:307786e72dde3f398ada1f7f7028d6b1d09e23a8a8817bd51f2c204e8ec695b1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('permissions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_019_permissions.sql
-- better-supabase module: permissions
-- @bsb-block permissions@1 managed
-- @bsb-hash sha256:712295b4a8567264242bbc8bca3e4cec3d67bd4b79011674f97174389ee4a6b6
-- can(), tenant_ids_with() and is_platform(): one permission contract for policies and SQL modules, over a roles list, a role and permission catalog, an authorization provider or the app's own functions (blocks.permissions.model).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
grant usage on schema better_supabase to supabase_auth_admin;
set check_function_bodies = off;
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
  select exists (select 1 from "better_supabase"."organizations" t where t."id" = tenant_disabled.tenant and (t."disabled_at" is not null or t."deleted_at" is not null))
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
reset check_function_bodies;

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
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'acknowledgements.acknowledge' then 'acknowledgements.acknowledge'
    when 'acknowledgements.manage' then 'acknowledgements.manage'
    when 'acknowledgements.read' then 'acknowledgements.read'
    when 'activities.manage' then 'activities.manage'
    when 'activities.read' then 'activities.read'
    when 'activities.write' then 'activities.write'
    when 'agents.create' then 'agents.create'
    when 'agents.moderate' then 'agents.moderate'
    when 'agents.publish' then 'agents.publish'
    when 'agents.read' then 'agents.read'
    when 'ai-chat.admin' then 'ai_chat.admin'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai_files.manage'
    when 'ai-files.upload' then 'ai_files.upload'
    when 'ai-keys.manage' then 'ai_keys.manage'
    when 'ai-keys.use' then 'ai_keys.use'
    when 'ai-schedules.create' then 'ai_schedules.create'
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
    when 'billing.manage' then 'billing.manage'
    when 'billing.read' then 'billing.read'
    when 'billing.viewAll' then 'billing.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk.run' then 'bulk.run'
    when 'calendar.manage' then 'calendar.manage'
    when 'calendar.read' then 'calendar.read'
    when 'calendar.write' then 'calendar.write'
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
    when 'collections.read' then 'collections.read'
    when 'collections.share' then 'collections.share'
    when 'collections.write' then 'collections.write'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'compliance.acknowledge' then 'compliance.acknowledge'
    when 'compliance.collect' then 'compliance.collect'
    when 'compliance.manage' then 'compliance.manage'
    when 'compliance.read' then 'compliance.read'
    when 'connectors.manage' then 'connectors.manage'
    when 'connectors.read' then 'connectors.read'
    when 'connectors.use' then 'connectors.use'
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
    when 'data-lifecycle.cancelDelete' then 'data_lifecycle.delete'
    when 'data-lifecycle.delete' then 'data_lifecycle.delete'
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
    when 'domains.manage' then 'domains.manage'
    when 'domains.read' then 'domains.read'
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
    when 'impersonation.revoke' then 'impersonation.revoke'
    when 'impersonation.start' then 'impersonation.start'
    when 'impersonation.view' then 'impersonation.read'
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
    when 'knowledge.manage' then 'knowledge.manage'
    when 'knowledge.read' then 'knowledge.read'
    when 'knowledge.write' then 'knowledge.write'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'leave.approve' then 'leave.approve'
    when 'leave.manage' then 'leave.manage'
    when 'leave.read' then 'leave.read'
    when 'leave.request' then 'leave.request'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'mail-sync.connect' then 'mail_sync.connect'
    when 'mail-sync.manage' then 'mail_sync.manage'
    when 'mail-sync.read' then 'mail_sync.read'
    when 'mail-sync.send' then 'mail_sync.send'
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
    when 'reviews.manage' then 'reviews.manage'
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
    when 'webhooks-in.create' then 'incoming_webhooks.manage'
    when 'webhooks-in.delete' then 'incoming_webhooks.manage'
    when 'webhooks-in.update' then 'incoming_webhooks.manage'
    when 'webhooks-in.view' then 'incoming_webhooks.read'
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

-- The roles model (blocks.permissions.roles): each role's permission keys.
create or replace function better_supabase.role_permissions(role text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case role
    when 'owner' then array['*']::text[]
    when 'admin' then array['organization.read', 'organization.update', 'members.*', 'audit.read', 'audit.revert', 'webhooks.*', 'notifications.*', 'billing.*', 'api_keys.*', 'settings.*', 'usage.*', 'timeline.read', 'attachments.*', 'data_lifecycle.*', 'incoming_webhooks.*', 'onboarding.*', 'inbox.*', 'ai_chat.*', 'ai_files.*', 'knowledge.*', 'memory.*', 'agents.*', 'connectors.*', 'ai_schedules.*', 'ai_keys.*', 'tags.*', 'teams.*', 'custom_fields.*', 'share_links.*', 'reminders.*', 'imports.*', 'saved_views.*', 'relations.*', 'bulk.*', 'search.*', 'metrics.*', 'calendar.*', 'bookings.*', 'versions.*', 'trash.*', 'reactions.*', 'approvals.*', 'access_requests.*', 'documents.*', 'drive.*', 'forms.*', 'signatures.*', 'templates.*', 'time_tracking.*', 'service_accounts.*', 'pipelines.*', 'contacts.*', 'activities.*', 'deals.*', 'tasks.*', 'quotes.*', 'invoices.*', 'sla.*', 'goals.*', 'hiring.*', 'employees.*', 'collections.*', 'messages.*', 'channels.*', 'mail_sync.*', 'segments.*', 'assignment.*', 'enrichment.*', 'forecasts.*', 'field_history.*', 'domains.*', 'automations.*', 'reviews.*', 'leave.*', 'ledger.*', 'assets.*', 'scores.*', 'moderation.*', 'enrollments.*', 'guests.*', 'passes.*', 'billable_time.*', 'leases.*', 'expenses.*', 'donations.*', 'dispatch.*', 'shipments.*', 'contracts.*', 'compliance.*', 'acknowledgements.*', 'cases.*', 'incidents.*', 'courses.*', 'sequences.*', 'posts.*', 'content.*']::text[]
    when 'member' then array['organization.read', 'members.read', 'notifications.read', 'api_keys.own', 'settings.read', 'timeline.read', 'attachments.read', 'attachments.upload', 'onboarding.read', 'inbox.read', 'inbox.reply', 'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_files.read', 'ai_files.upload', 'knowledge.read', 'memory.read', 'agents.read', 'agents.create', 'agents.publish', 'connectors.read', 'connectors.use', 'ai_schedules.create', 'custom_fields.read', 'teams.read', 'tags.read', 'tags.apply', 'share_links.read', 'reminders.read', 'saved_views.read', 'relations.read', 'bulk.run', 'search.read', 'metrics.read', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'versions.restore', 'trash.read', 'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read', 'approvals.request', 'access_requests.create', 'documents.read', 'documents.write', 'documents.suggest', 'drive.read', 'drive.create', 'forms.read', 'forms.submit', 'signatures.read', 'signatures.request', 'templates.read', 'templates.apply', 'time_tracking.track', 'leave.request', 'pipelines.read', 'contacts.read', 'contacts.write', 'activities.read', 'activities.write', 'deals.read', 'deals.write', 'tasks.read', 'tasks.write', 'quotes.read', 'quotes.write', 'invoices.read', 'sla.read', 'goals.read', 'employees.read', 'collections.read', 'collections.write', 'domains.read', 'automations.read', 'assets.read', 'scores.read', 'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit', 'dispatch.read', 'dispatch.work', 'shipments.read', 'contracts.read', 'contracts.write', 'compliance.read', 'compliance.collect', 'compliance.acknowledge', 'acknowledgements.acknowledge', 'cases.read', 'cases.create', 'incidents.read', 'incidents.write', 'courses.read', 'sequences.read', 'sequences.enroll', 'posts.read', 'posts.write', 'content.read', 'content.write', 'messages.read', 'messages.send', 'channels.create', 'mail_sync.read', 'mail_sync.connect', 'mail_sync.send', 'segments.read', 'assignment.read', 'enrichment.read', 'forecasts.read', 'field_history.read']::text[]
    when 'viewer' then array['organization.read']::text[]
    else '{}'::text[]
  end
$$;

create or replace function better_supabase.role_grants(role text, permission text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select exists (
    select 1 from unnest(better_supabase.role_permissions(role)) g(key)
    where better_supabase.permission_matches(g.key, permission)
  )
$$;
revoke execute on function better_supabase.role_permissions(text) from public, anon, authenticated;
revoke execute on function better_supabase.role_grants(text, text) from public, anon, authenticated;
grant execute on function better_supabase.role_permissions(text) to service_role, supabase_auth_admin;
grant execute on function better_supabase.role_grants(text, text) to service_role, supabase_auth_admin;

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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = member_can.tenant and m."user_id" = member_can.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can.permission)
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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = member_can_while_deleting.tenant and m."user_id" = member_can_while_deleting.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can_while_deleting.permission)
    )
$$;

-- The permission keys a member holds in a tenant (wildcards as configured).
create or replace function better_supabase.member_permissions(member uuid, tenant uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
      select better_supabase.role_permissions(m."role") from "better_supabase"."memberships" m
      where m."organization_id" = member_permissions.tenant and m."user_id" = member_permissions.member and m."disabled_at" is null
    ), '{}'::text[])
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
    and ((platform_can.member = auth.uid() and exists (
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
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
    and better_supabase.cap_allows(tenant_ids_with.permission)
    and better_supabase.role_grants(m."role", tenant_ids_with.permission)
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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = can_assign_as.tenant and m."user_id" = can_assign_as.member and m."disabled_at" is null
    )
    and not exists (
      select 1 from unnest(better_supabase.role_permissions(can_assign_as.role)) k(key) where true
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


create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(m."organization_id"::text, to_jsonb(better_supabase.member_permissions(m."user_id", m."organization_id"))), '{}'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = permission_claims.user_id
    and not better_supabase.user_disabled(permission_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
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
drop function if exists "better_supabase"."list_roles"(uuid);
drop function if exists "better_supabase"."set_permission_override"(uuid, text, text, boolean);

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_019_permissions.sql
-- better-supabase module: permissions
-- @bsb-block-data permissions
-- @bsb-hash sha256:307786e72dde3f398ada1f7f7028d6b1d09e23a8a8817bd51f2c204e8ec695b1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('permissions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_019_permissions.sql
-- better-supabase module: permissions
-- @bsb-block permissions@1 managed
-- @bsb-hash sha256:6f1eef3bbeb337cf530fae23d3cfbb6b7480a724aa55fed519bb3f751cc8920c
-- can(), tenant_ids_with() and is_platform(): one permission contract for policies and SQL modules, over a roles list, a role and permission catalog, an authorization provider or the app's own functions (blocks.permissions.model).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
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
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
  end
$$;

-- The roles model (blocks.permissions.roles): each role's permission keys.
create or replace function better_supabase.role_permissions(role text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case role
    when 'owner' then array['*']::text[]
    when 'admin' then array['organization.read', 'organization.update', 'members.*', 'audit.read', 'audit.revert', 'webhooks.*', 'notifications.*', 'billing.*', 'api_keys.*', 'settings.*', 'usage.*', 'timeline.read', 'attachments.*', 'data_lifecycle.*', 'incoming_webhooks.*', 'onboarding.*', 'inbox.*', 'ai_chat.*', 'ai_files.*', 'knowledge.*', 'memory.*', 'agents.*', 'connectors.*', 'ai_schedules.*', 'ai_keys.*', 'tags.*', 'teams.*', 'custom_fields.*', 'share_links.*', 'reminders.*', 'imports.*', 'saved_views.*', 'relations.*', 'bulk.*', 'search.*', 'metrics.*', 'calendar.*', 'bookings.*', 'versions.*', 'trash.*', 'reactions.*', 'approvals.*', 'access_requests.*', 'documents.*', 'drive.*', 'forms.*', 'signatures.*', 'templates.*', 'time_tracking.*', 'service_accounts.*', 'pipelines.*', 'contacts.*', 'activities.*', 'deals.*', 'tasks.*', 'quotes.*', 'invoices.*', 'sla.*', 'goals.*', 'hiring.*', 'employees.*', 'collections.*', 'messages.*', 'channels.*', 'mail_sync.*', 'segments.*', 'assignment.*', 'enrichment.*', 'forecasts.*', 'field_history.*', 'domains.*', 'automations.*', 'reviews.*', 'leave.*', 'ledger.*', 'assets.*', 'scores.*', 'moderation.*', 'enrollments.*', 'guests.*', 'passes.*', 'billable_time.*', 'leases.*', 'expenses.*', 'donations.*', 'dispatch.*', 'shipments.*', 'contracts.*', 'compliance.*', 'acknowledgements.*', 'cases.*', 'incidents.*', 'courses.*', 'sequences.*', 'posts.*', 'content.*']::text[]
    when 'member' then array['organization.read', 'members.read', 'notifications.read', 'api_keys.own', 'settings.read', 'timeline.read', 'attachments.read', 'attachments.upload', 'onboarding.read', 'inbox.read', 'inbox.reply', 'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_files.read', 'ai_files.upload', 'knowledge.read', 'memory.read', 'agents.read', 'agents.create', 'agents.publish', 'connectors.read', 'connectors.use', 'ai_schedules.create', 'custom_fields.read', 'teams.read', 'tags.read', 'tags.apply', 'share_links.read', 'reminders.read', 'saved_views.read', 'relations.read', 'bulk.run', 'search.read', 'metrics.read', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'versions.restore', 'trash.read', 'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read', 'approvals.request', 'access_requests.create', 'documents.read', 'documents.write', 'documents.suggest', 'drive.read', 'drive.create', 'forms.read', 'forms.submit', 'signatures.read', 'signatures.request', 'templates.read', 'templates.apply', 'time_tracking.track', 'leave.request', 'pipelines.read', 'contacts.read', 'contacts.write', 'activities.read', 'activities.write', 'deals.read', 'deals.write', 'tasks.read', 'tasks.write', 'quotes.read', 'quotes.write', 'invoices.read', 'sla.read', 'goals.read', 'employees.read', 'collections.read', 'collections.write', 'domains.read', 'automations.read', 'assets.read', 'scores.read', 'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit', 'dispatch.read', 'dispatch.work', 'shipments.read', 'contracts.read', 'contracts.write', 'compliance.read', 'compliance.collect', 'compliance.acknowledge', 'acknowledgements.acknowledge', 'cases.read', 'cases.create', 'incidents.read', 'incidents.write', 'courses.read', 'sequences.read', 'sequences.enroll', 'posts.read', 'posts.write', 'content.read', 'content.write', 'messages.read', 'messages.send', 'channels.create', 'mail_sync.read', 'mail_sync.connect', 'mail_sync.send', 'segments.read', 'assignment.read', 'enrichment.read', 'forecasts.read', 'field_history.read']::text[]
    when 'viewer' then array['organization.read']::text[]
    else '{}'::text[]
  end
$$;

create or replace function better_supabase.role_grants(role text, permission text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select exists (
    select 1 from unnest(better_supabase.role_permissions(role)) g(key)
    where better_supabase.permission_matches(g.key, permission)
  )
$$;
revoke execute on function better_supabase.role_permissions(text) from public, anon, authenticated;
revoke execute on function better_supabase.role_grants(text, text) from public, anon, authenticated;
grant execute on function better_supabase.role_permissions(text) to service_role, supabase_auth_admin;
grant execute on function better_supabase.role_grants(text, text) to service_role, supabase_auth_admin;

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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = member_can.tenant and m."user_id" = member_can.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can.permission)
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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = member_can_while_deleting.tenant and m."user_id" = member_can_while_deleting.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can_while_deleting.permission)
    )
$$;

-- The permission keys a member holds in a tenant (wildcards as configured).
create or replace function better_supabase.member_permissions(member uuid, tenant uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
      select better_supabase.role_permissions(m."role") from "better_supabase"."memberships" m
      where m."organization_id" = member_permissions.tenant and m."user_id" = member_permissions.member and m."disabled_at" is null
    ), '{}'::text[])
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
    and ((platform_can.member = auth.uid() and exists (
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
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
    and better_supabase.cap_allows(tenant_ids_with.permission)
    and better_supabase.role_grants(m."role", tenant_ids_with.permission)
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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = can_assign_as.tenant and m."user_id" = can_assign_as.member and m."disabled_at" is null
    )
    and not exists (
      select 1 from unnest(better_supabase.role_permissions(can_assign_as.role)) k(key) where true
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


create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(m."organization_id"::text, to_jsonb(better_supabase.member_permissions(m."user_id", m."organization_id"))), '{}'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = permission_claims.user_id
    and not better_supabase.user_disabled(permission_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
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
drop function if exists "better_supabase"."list_roles"(uuid);
drop function if exists "better_supabase"."set_permission_override"(uuid, text, text, boolean);

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_019_permissions.sql
-- better-supabase module: permissions
-- @bsb-block-data permissions
-- @bsb-hash sha256:307786e72dde3f398ada1f7f7028d6b1d09e23a8a8817bd51f2c204e8ec695b1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('permissions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_019_permissions.sql
-- better-supabase module: permissions
-- @bsb-block permissions@1 managed
-- @bsb-hash sha256:5d60d82afb60beb96f1212985e7a39c65e3243d331a06caf1ec8d9ef60cbf678
-- can(), tenant_ids_with() and is_platform(): one permission contract for policies and SQL modules, over a roles list, a role and permission catalog, an authorization provider or the app's own functions (blocks.permissions.model).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
  end
$$;

-- The roles model (blocks.permissions.roles): each role's permission keys.
create or replace function better_supabase.role_permissions(role text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case role
    when 'owner' then array['*']::text[]
    when 'admin' then array['organization.read', 'organization.update', 'members.*', 'audit.read', 'audit.revert', 'webhooks.*', 'notifications.*', 'billing.*', 'api_keys.*', 'settings.*', 'usage.*', 'timeline.read', 'attachments.*', 'data_lifecycle.*', 'incoming_webhooks.*', 'onboarding.*', 'inbox.*', 'ai_chat.*', 'ai_files.*', 'knowledge.*', 'memory.*', 'agents.*', 'connectors.*', 'ai_schedules.*', 'ai_keys.*', 'tags.*', 'teams.*', 'custom_fields.*', 'share_links.*', 'reminders.*', 'imports.*', 'saved_views.*', 'relations.*', 'bulk.*', 'search.*', 'metrics.*', 'calendar.*', 'bookings.*', 'versions.*', 'trash.*', 'reactions.*', 'approvals.*', 'access_requests.*', 'documents.*', 'drive.*', 'forms.*', 'signatures.*', 'templates.*', 'time_tracking.*', 'service_accounts.*', 'pipelines.*', 'contacts.*', 'activities.*', 'deals.*', 'tasks.*', 'quotes.*', 'invoices.*', 'sla.*', 'goals.*', 'hiring.*', 'employees.*', 'collections.*', 'messages.*', 'channels.*', 'mail_sync.*', 'segments.*', 'assignment.*', 'enrichment.*', 'forecasts.*', 'field_history.*', 'domains.*', 'automations.*', 'reviews.*', 'leave.*', 'ledger.*', 'assets.*', 'scores.*', 'moderation.*', 'enrollments.*', 'guests.*', 'passes.*', 'billable_time.*', 'leases.*', 'expenses.*', 'donations.*', 'dispatch.*', 'shipments.*', 'contracts.*', 'compliance.*', 'acknowledgements.*', 'cases.*', 'incidents.*', 'courses.*', 'sequences.*', 'posts.*', 'content.*']::text[]
    when 'member' then array['organization.read', 'members.read', 'notifications.read', 'api_keys.own', 'settings.read', 'timeline.read', 'attachments.read', 'attachments.upload', 'onboarding.read', 'inbox.read', 'inbox.reply', 'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_files.read', 'ai_files.upload', 'knowledge.read', 'memory.read', 'agents.read', 'agents.create', 'agents.publish', 'connectors.read', 'connectors.use', 'ai_schedules.create', 'custom_fields.read', 'teams.read', 'tags.read', 'tags.apply', 'share_links.read', 'reminders.read', 'saved_views.read', 'relations.read', 'bulk.run', 'search.read', 'metrics.read', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'versions.restore', 'trash.read', 'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read', 'approvals.request', 'access_requests.create', 'documents.read', 'documents.write', 'documents.suggest', 'drive.read', 'drive.create', 'forms.read', 'forms.submit', 'signatures.read', 'signatures.request', 'templates.read', 'templates.apply', 'time_tracking.track', 'leave.request', 'pipelines.read', 'contacts.read', 'contacts.write', 'activities.read', 'activities.write', 'deals.read', 'deals.write', 'tasks.read', 'tasks.write', 'quotes.read', 'quotes.write', 'invoices.read', 'sla.read', 'goals.read', 'employees.read', 'collections.read', 'collections.write', 'domains.read', 'automations.read', 'assets.read', 'scores.read', 'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit', 'dispatch.read', 'dispatch.work', 'shipments.read', 'contracts.read', 'contracts.write', 'compliance.read', 'compliance.collect', 'compliance.acknowledge', 'acknowledgements.acknowledge', 'cases.read', 'cases.create', 'incidents.read', 'incidents.write', 'courses.read', 'sequences.read', 'sequences.enroll', 'posts.read', 'posts.write', 'content.read', 'content.write', 'messages.read', 'messages.send', 'channels.create', 'mail_sync.read', 'mail_sync.connect', 'mail_sync.send', 'segments.read', 'assignment.read', 'enrichment.read', 'forecasts.read', 'field_history.read']::text[]
    when 'viewer' then array['organization.read']::text[]
    else '{}'::text[]
  end
$$;

create or replace function better_supabase.role_grants(role text, permission text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select exists (
    select 1 from unnest(better_supabase.role_permissions(role)) g(key)
    where better_supabase.permission_matches(g.key, permission)
  )
$$;
revoke execute on function better_supabase.role_permissions(text) from public, anon, authenticated;
revoke execute on function better_supabase.role_grants(text, text) from public, anon, authenticated;
grant execute on function better_supabase.role_permissions(text) to service_role, supabase_auth_admin;
grant execute on function better_supabase.role_grants(text, text) to service_role, supabase_auth_admin;

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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = member_can.tenant and m."user_id" = member_can.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can.permission)
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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = member_can_while_deleting.tenant and m."user_id" = member_can_while_deleting.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can_while_deleting.permission)
    )
$$;

-- The permission keys a member holds in a tenant (wildcards as configured).
create or replace function better_supabase.member_permissions(member uuid, tenant uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
      select better_supabase.role_permissions(m."role") from "better_supabase"."memberships" m
      where m."organization_id" = member_permissions.tenant and m."user_id" = member_permissions.member and m."disabled_at" is null
    ), '{}'::text[])
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
    and ((platform_can.member = auth.uid() and exists (
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
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
    and better_supabase.cap_allows(tenant_ids_with.permission)
    and better_supabase.role_grants(m."role", tenant_ids_with.permission)
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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = can_assign_as.tenant and m."user_id" = can_assign_as.member and m."disabled_at" is null
    )
    and not exists (
      select 1 from unnest(better_supabase.role_permissions(can_assign_as.role)) k(key) where true
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


create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(m."organization_id"::text, to_jsonb(better_supabase.member_permissions(m."user_id", m."organization_id"))), '{}'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = permission_claims.user_id
    and not better_supabase.user_disabled(permission_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
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
drop function if exists "better_supabase"."list_roles"(uuid);
drop function if exists "better_supabase"."set_permission_override"(uuid, text, text, boolean);

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

create or replace function "api"."role_permissions"(role text)
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."role_permissions"($1) $$;
revoke execute on function "api"."role_permissions"(text) from public, anon, authenticated;
grant execute on function "api"."role_permissions"(text) to service_role;

create or replace function "api"."role_grants"(role text, permission text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."role_grants"($1, $2) $$;
revoke execute on function "api"."role_grants"(text, text) from public, anon, authenticated;
grant execute on function "api"."role_grants"(text, text) to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_019_permissions.sql
-- better-supabase module: permissions
-- @bsb-block-data permissions
-- @bsb-hash sha256:307786e72dde3f398ada1f7f7028d6b1d09e23a8a8817bd51f2c204e8ec695b1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('permissions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_019_permissions.sql
-- better-supabase module: permissions
-- @bsb-block permissions@1 managed
-- @bsb-hash sha256:40e9199a4240b87a025c7da3485a4e0a058116da411699fbe842ecdc6cc63a59
-- can(), tenant_ids_with() and is_platform(): one permission contract for policies and SQL modules, over a roles list, a role and permission catalog, an authorization provider or the app's own functions (blocks.permissions.model).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
  end
$$;

-- The roles model (blocks.permissions.roles): each role's permission keys.
create or replace function better_supabase.role_permissions(role text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case role
    when 'owner' then array['*']::text[]
    when 'admin' then array['organization.read', 'organization.update', 'members.*', 'audit.read', 'audit.revert', 'webhooks.*', 'notifications.*', 'billing.*', 'api_keys.*', 'settings.*', 'usage.*', 'timeline.read', 'attachments.*', 'data_lifecycle.*', 'incoming_webhooks.*', 'onboarding.*', 'inbox.*', 'ai_chat.*', 'ai_files.*', 'knowledge.*', 'memory.*', 'agents.*', 'connectors.*', 'ai_schedules.*', 'ai_keys.*', 'tags.*', 'teams.*', 'custom_fields.*', 'share_links.*', 'reminders.*', 'imports.*', 'saved_views.*', 'relations.*', 'bulk.*', 'search.*', 'metrics.*', 'calendar.*', 'bookings.*', 'versions.*', 'trash.*', 'reactions.*', 'approvals.*', 'access_requests.*', 'documents.*', 'drive.*', 'forms.*', 'signatures.*', 'templates.*', 'time_tracking.*', 'service_accounts.*', 'pipelines.*', 'contacts.*', 'activities.*', 'deals.*', 'tasks.*', 'quotes.*', 'invoices.*', 'sla.*', 'goals.*', 'hiring.*', 'employees.*', 'collections.*', 'messages.*', 'channels.*', 'mail_sync.*', 'segments.*', 'assignment.*', 'enrichment.*', 'forecasts.*', 'field_history.*', 'domains.*', 'automations.*', 'reviews.*', 'leave.*', 'ledger.*', 'assets.*', 'scores.*', 'moderation.*', 'enrollments.*', 'guests.*', 'passes.*', 'billable_time.*', 'leases.*', 'expenses.*', 'donations.*', 'dispatch.*', 'shipments.*', 'contracts.*', 'compliance.*', 'acknowledgements.*', 'cases.*', 'incidents.*', 'courses.*', 'sequences.*', 'posts.*', 'content.*']::text[]
    when 'member' then array['organization.read', 'members.read', 'notifications.read', 'api_keys.own', 'settings.read', 'timeline.read', 'attachments.read', 'attachments.upload', 'onboarding.read', 'inbox.read', 'inbox.reply', 'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_files.read', 'ai_files.upload', 'knowledge.read', 'memory.read', 'agents.read', 'agents.create', 'agents.publish', 'connectors.read', 'connectors.use', 'ai_schedules.create', 'custom_fields.read', 'teams.read', 'tags.read', 'tags.apply', 'share_links.read', 'reminders.read', 'saved_views.read', 'relations.read', 'bulk.run', 'search.read', 'metrics.read', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'versions.restore', 'trash.read', 'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read', 'approvals.request', 'access_requests.create', 'documents.read', 'documents.write', 'documents.suggest', 'drive.read', 'drive.create', 'forms.read', 'forms.submit', 'signatures.read', 'signatures.request', 'templates.read', 'templates.apply', 'time_tracking.track', 'leave.request', 'pipelines.read', 'contacts.read', 'contacts.write', 'activities.read', 'activities.write', 'deals.read', 'deals.write', 'tasks.read', 'tasks.write', 'quotes.read', 'quotes.write', 'invoices.read', 'sla.read', 'goals.read', 'employees.read', 'collections.read', 'collections.write', 'domains.read', 'automations.read', 'assets.read', 'scores.read', 'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit', 'dispatch.read', 'dispatch.work', 'shipments.read', 'contracts.read', 'contracts.write', 'compliance.read', 'compliance.collect', 'compliance.acknowledge', 'acknowledgements.acknowledge', 'cases.read', 'cases.create', 'incidents.read', 'incidents.write', 'courses.read', 'sequences.read', 'sequences.enroll', 'posts.read', 'posts.write', 'content.read', 'content.write', 'messages.read', 'messages.send', 'channels.create', 'mail_sync.read', 'mail_sync.connect', 'mail_sync.send', 'segments.read', 'assignment.read', 'enrichment.read', 'forecasts.read', 'field_history.read']::text[]
    when 'viewer' then array['organization.read']::text[]
    else '{}'::text[]
  end
$$;

create or replace function better_supabase.role_grants(role text, permission text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select exists (
    select 1 from unnest(better_supabase.role_permissions(role)) g(key)
    where better_supabase.permission_matches(g.key, permission)
  )
$$;
revoke execute on function better_supabase.role_permissions(text) from public, anon, authenticated;
revoke execute on function better_supabase.role_grants(text, text) from public, anon, authenticated;
grant execute on function better_supabase.role_permissions(text) to service_role, supabase_auth_admin;
grant execute on function better_supabase.role_grants(text, text) to service_role, supabase_auth_admin;

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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = member_can.tenant and m."user_id" = member_can.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can.permission)
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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = member_can_while_deleting.tenant and m."user_id" = member_can_while_deleting.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can_while_deleting.permission)
    )
$$;

-- The permission keys a member holds in a tenant (wildcards as configured).
create or replace function better_supabase.member_permissions(member uuid, tenant uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
      select better_supabase.role_permissions(m."role") from "better_supabase"."memberships" m
      where m."organization_id" = member_permissions.tenant and m."user_id" = member_permissions.member and m."disabled_at" is null
    ), '{}'::text[])
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
    and ((platform_can.member = auth.uid() and exists (
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
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
    and better_supabase.cap_allows(tenant_ids_with.permission)
    and better_supabase.role_grants(m."role", tenant_ids_with.permission)
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
      select 1 from "better_supabase"."memberships" m
      where m."organization_id" = can_assign_as.tenant and m."user_id" = can_assign_as.member and m."disabled_at" is null
    )
    and not exists (
      select 1 from unnest(better_supabase.role_permissions(can_assign_as.role)) k(key) where true
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


create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(m."organization_id"::text, to_jsonb(better_supabase.member_permissions(m."user_id", m."organization_id"))), '{}'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = permission_claims.user_id
    and not better_supabase.user_disabled(permission_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
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
drop function if exists "better_supabase"."list_roles"(uuid);
drop function if exists "better_supabase"."set_permission_override"(uuid, text, text, boolean);

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_019_permissions.sql
-- better-supabase module: permissions
-- @bsb-block-data permissions
-- @bsb-hash sha256:307786e72dde3f398ada1f7f7028d6b1d09e23a8a8817bd51f2c204e8ec695b1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('permissions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_019_permissions.sql
-- better-supabase module: permissions
-- @bsb-block permissions@1 managed
-- @bsb-hash sha256:dffd34de3510914d8a0c8e972464e751affce365b1272a2e8a1aae27707aff2d
-- can(), tenant_ids_with() and is_platform(): one permission contract for policies and SQL modules, over a roles list, a role and permission catalog, an authorization provider or the app's own functions (blocks.permissions.model).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
  end
$$;

-- The roles model (blocks.permissions.roles): each role's permission keys.
create or replace function better_supabase.role_permissions(role text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case role
    when 'owner' then array['*']::text[]
    when 'admin' then array['organization.read', 'organization.update', 'members.*', 'audit.read', 'audit.revert', 'webhooks.*', 'notifications.*', 'billing.*', 'api_keys.*', 'settings.*', 'usage.*', 'timeline.read', 'attachments.*', 'data_lifecycle.*', 'incoming_webhooks.*', 'onboarding.*', 'inbox.*', 'ai_chat.*', 'ai_files.*', 'knowledge.*', 'memory.*', 'agents.*', 'connectors.*', 'ai_schedules.*', 'ai_keys.*', 'tags.*', 'teams.*', 'custom_fields.*', 'share_links.*', 'reminders.*', 'imports.*', 'saved_views.*', 'relations.*', 'bulk.*', 'search.*', 'metrics.*', 'calendar.*', 'bookings.*', 'versions.*', 'trash.*', 'reactions.*', 'approvals.*', 'access_requests.*', 'documents.*', 'drive.*', 'forms.*', 'signatures.*', 'templates.*', 'time_tracking.*', 'service_accounts.*', 'pipelines.*', 'contacts.*', 'activities.*', 'deals.*', 'tasks.*', 'quotes.*', 'invoices.*', 'sla.*', 'goals.*', 'hiring.*', 'employees.*', 'collections.*', 'messages.*', 'channels.*', 'mail_sync.*', 'segments.*', 'assignment.*', 'enrichment.*', 'forecasts.*', 'field_history.*', 'domains.*', 'automations.*', 'reviews.*', 'leave.*', 'ledger.*', 'assets.*', 'scores.*', 'moderation.*', 'enrollments.*', 'guests.*', 'passes.*', 'billable_time.*', 'leases.*', 'expenses.*', 'donations.*', 'dispatch.*', 'shipments.*', 'contracts.*', 'compliance.*', 'acknowledgements.*', 'cases.*', 'incidents.*', 'courses.*', 'sequences.*', 'posts.*', 'content.*']::text[]
    when 'member' then array['organization.read', 'members.read', 'notifications.read', 'api_keys.own', 'settings.read', 'timeline.read', 'attachments.read', 'attachments.upload', 'onboarding.read', 'inbox.read', 'inbox.reply', 'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_files.read', 'ai_files.upload', 'knowledge.read', 'memory.read', 'agents.read', 'agents.create', 'agents.publish', 'connectors.read', 'connectors.use', 'ai_schedules.create', 'custom_fields.read', 'teams.read', 'tags.read', 'tags.apply', 'share_links.read', 'reminders.read', 'saved_views.read', 'relations.read', 'bulk.run', 'search.read', 'metrics.read', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'versions.restore', 'trash.read', 'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read', 'approvals.request', 'access_requests.create', 'documents.read', 'documents.write', 'documents.suggest', 'drive.read', 'drive.create', 'forms.read', 'forms.submit', 'signatures.read', 'signatures.request', 'templates.read', 'templates.apply', 'time_tracking.track', 'leave.request', 'pipelines.read', 'contacts.read', 'contacts.write', 'activities.read', 'activities.write', 'deals.read', 'deals.write', 'tasks.read', 'tasks.write', 'quotes.read', 'quotes.write', 'invoices.read', 'sla.read', 'goals.read', 'employees.read', 'collections.read', 'collections.write', 'domains.read', 'automations.read', 'assets.read', 'scores.read', 'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit', 'dispatch.read', 'dispatch.work', 'shipments.read', 'contracts.read', 'contracts.write', 'compliance.read', 'compliance.collect', 'compliance.acknowledge', 'acknowledgements.acknowledge', 'cases.read', 'cases.create', 'incidents.read', 'incidents.write', 'courses.read', 'sequences.read', 'sequences.enroll', 'posts.read', 'posts.write', 'content.read', 'content.write', 'messages.read', 'messages.send', 'channels.create', 'mail_sync.read', 'mail_sync.connect', 'mail_sync.send', 'segments.read', 'assignment.read', 'enrichment.read', 'forecasts.read', 'field_history.read']::text[]
    when 'viewer' then array['organization.read']::text[]
    else '{}'::text[]
  end
$$;

create or replace function better_supabase.role_grants(role text, permission text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select exists (
    select 1 from unnest(better_supabase.role_permissions(role)) g(key)
    where better_supabase.permission_matches(g.key, permission)
  )
$$;
revoke execute on function better_supabase.role_permissions(text) from public, anon, authenticated;
revoke execute on function better_supabase.role_grants(text, text) from public, anon, authenticated;
grant execute on function better_supabase.role_permissions(text) to service_role, supabase_auth_admin;
grant execute on function better_supabase.role_grants(text, text) to service_role, supabase_auth_admin;

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
      select 1 from "better_supabase"."memberships" m
      where m."org_id" = member_can.tenant and m."user_id" = member_can.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can.permission)
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
      select 1 from "better_supabase"."memberships" m
      where m."org_id" = member_can_while_deleting.tenant and m."user_id" = member_can_while_deleting.member and m."disabled_at" is null
        and better_supabase.role_grants(m."role", member_can_while_deleting.permission)
    )
$$;

-- The permission keys a member holds in a tenant (wildcards as configured).
create or replace function better_supabase.member_permissions(member uuid, tenant uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
      select better_supabase.role_permissions(m."role") from "better_supabase"."memberships" m
      where m."org_id" = member_permissions.tenant and m."user_id" = member_permissions.member and m."disabled_at" is null
    ), '{}'::text[])
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
    and ((platform_can.member = auth.uid() and exists (
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
  select m."org_id"
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and not better_supabase.user_disabled(auth.uid())
    and not better_supabase.tenant_disabled(m."org_id") and m."disabled_at" is null
    and better_supabase.cap_allows(tenant_ids_with.permission)
    and better_supabase.role_grants(m."role", tenant_ids_with.permission)
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
      select 1 from "better_supabase"."memberships" m
      where m."org_id" = can_assign_as.tenant and m."user_id" = can_assign_as.member and m."disabled_at" is null
    )
    and not exists (
      select 1 from unnest(better_supabase.role_permissions(can_assign_as.role)) k(key) where true
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


create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(m."org_id"::text, to_jsonb(better_supabase.member_permissions(m."user_id", m."org_id"))), '{}'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = permission_claims.user_id
    and not better_supabase.user_disabled(permission_claims.user_id)
    and not better_supabase.tenant_disabled(m."org_id") and m."disabled_at" is null
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
drop function if exists "better_supabase"."list_roles"(uuid);
drop function if exists "better_supabase"."set_permission_override"(uuid, text, text, boolean);

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_019_permissions.sql
-- better-supabase module: permissions
-- @bsb-block-data permissions
-- @bsb-hash sha256:307786e72dde3f398ada1f7f7028d6b1d09e23a8a8817bd51f2c204e8ec695b1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('permissions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
