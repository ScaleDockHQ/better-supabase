-- ==== memberships
-- better-supabase module: memberships
-- @bsb-block memberships@3 managed
-- @bsb-hash sha256:a5f4c0d973dedcab393775fbfb0e879cba8ca58f7d7597dd84541ba2ad93b17e
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

grant usage on schema better_supabase to supabase_auth_admin;
set check_function_bodies = off;

create table "better_supabase"."memberships" (
  "organization_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role" text not null default 'member',
  "created_at" timestamptz not null default now(),
  primary key ("organization_id", "user_id")
);
create index memberships_user_idx on "better_supabase"."memberships" ("user_id");
alter table "better_supabase"."memberships" add column "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "better_supabase"."memberships"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."memberships" add column "last_used_at" timestamptz;
alter table "better_supabase"."memberships" add column "disabled_at" timestamptz;
alter table "better_supabase"."memberships"
  add constraint bsb_memberships_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

alter table "better_supabase"."memberships" enable row level security;
grant select on "better_supabase"."memberships" to authenticated;
grant all on "better_supabase"."memberships" to service_role;

-- blocks.memberships.options.roles.many: every membership holds a set of
-- roles. "better_supabase"."memberships"."role" keeps the highest-ranked one (the order of
-- blocks.permissions.roles), so readers of the single role keep working.
create table "better_supabase"."membership_roles" (
  "organization_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null,
  "created_at" timestamptz not null default now(),
  primary key ("organization_id", "user_id", "role"),
  foreign key ("organization_id", "user_id") references "better_supabase"."memberships" ("organization_id", "user_id") on delete cascade
);
create index membership_roles_user_idx on "better_supabase"."membership_roles" ("user_id");
alter table "better_supabase"."membership_roles"
  add constraint bsb_membership_roles_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));
alter table "better_supabase"."membership_roles" enable row level security;
grant select on "better_supabase"."membership_roles" to authenticated;
grant all on "better_supabase"."membership_roles" to service_role;

-- Writing "role" directly (update_member_role, a client policy, the service
-- role) swaps the previous primary role for the new one and keeps the written
-- one primary. The member's other roles, custom ones included, stay in the set.
create or replace function "better_supabase"."membership_roles_from_role"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."role" is null or current_setting('better_supabase.membership_role_sync', true) = 'on' then
    return null;
  end if;
  perform set_config('better_supabase.membership_role_sync', 'on', true);
  if tg_op = 'UPDATE' and old."role" is not null and old."role"::text <> new."role"::text then
    delete from "better_supabase"."membership_roles" r where r."organization_id" = new."organization_id" and r."user_id" = new."user_id" and r."role" = old."role"::text;
  end if;
  insert into "better_supabase"."membership_roles" ("organization_id", "user_id", "role") values (new."organization_id", new."user_id", new."role"::text)
  on conflict do nothing;
  perform set_config('better_supabase.membership_role_sync', '', true);
  return null;
end;
$$;
revoke execute on function "better_supabase"."membership_roles_from_role"() from public, anon, authenticated;
create trigger "bsb_membership_roles" after insert or update of "role" on "better_supabase"."memberships"
  for each row execute function "better_supabase"."membership_roles_from_role"();

-- Adding or removing a role moves "role" to the highest-ranked one left. An
-- emptied set leaves it alone; remove_member_role refuses the last role.
create or replace function "better_supabase"."membership_role_from_roles"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(new."organization_id", old."organization_id");
  v_user uuid := coalesce(new."user_id", old."user_id");
  v_primary text;
begin
  if current_setting('better_supabase.membership_role_sync', true) = 'on' then
    return null;
  end if;
  select r."role" into v_primary from "better_supabase"."membership_roles" r
  where r."organization_id" = v_tenant and r."user_id" = v_user
  order by array_position(array['owner', 'admin', 'member', 'viewer']::text[], r."role"), r."role"
  limit 1;
  if v_primary is not null then
    perform set_config('better_supabase.membership_role_sync', 'on', true);
    update "better_supabase"."memberships" m set "role" = v_primary
    where m."organization_id" = v_tenant and m."user_id" = v_user and m."role"::text is distinct from v_primary;
    perform set_config('better_supabase.membership_role_sync', '', true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."membership_role_from_roles"() from public, anon, authenticated;
create trigger "bsb_membership_role_primary" after insert or delete on "better_supabase"."membership_roles"
  for each row execute function "better_supabase"."membership_role_from_roles"();


-- The tenant the server resolved (the better_supabase.tenant setting over Postgres,
-- the x-bsb-tenant header over the Data API), then the `tenant_id` claim.
-- A tenant the caller isn't a member of counts as none.
create or replace function better_supabase.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(current_setting('better_supabase.tenant', true), '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(current_setting('request.headers', true)::jsonb ->> 'x-bsb-tenant', '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '') and m."user_id" = auth.uid() limit 1)
  )::uuid
$$;
revoke execute on function better_supabase.current_tenant_id() from public;
grant execute on function better_supabase.current_tenant_id() to anon, authenticated, service_role, supabase_auth_admin;

-- Policies compare against the set once per statement:
--   using (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')))
-- has_organization_role(organization) answers for one organization, in functions and checks.
-- Prefer the access contract (better_supabase.can, tenant_ids_with) for
-- permission checks; these answer by role name.
create or replace function better_supabase.member_organization_ids(roles text[] default null)
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
    and (member_organization_ids.roles is null or exists (select 1 from "better_supabase"."membership_roles" mr where mr."organization_id" = m."organization_id" and mr."user_id" = m."user_id" and mr."role" = any (member_organization_ids.roles)))
    and not better_supabase.user_disabled(m."user_id")
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$$;

create or replace function better_supabase.has_organization_role(organization uuid, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from "better_supabase"."memberships" m
    where m."organization_id" = has_organization_role.organization
      and m."user_id" = auth.uid()
      and (has_organization_role.roles is null or exists (select 1 from "better_supabase"."membership_roles" mr where mr."organization_id" = m."organization_id" and mr."user_id" = m."user_id" and mr."role" = any (has_organization_role.roles)))
      and not better_supabase.user_disabled(m."user_id")
      and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
  )
$$;

-- The role of a user in a tenant, or null when they aren't a member.
create or replace function better_supabase.organization_member_role(organization uuid, member uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m."role" from "better_supabase"."memberships" m where m."organization_id" = organization_member_role.organization and m."user_id" = organization_member_role.member and m."disabled_at" is null
$$;

-- The roles of a user in a tenant, highest-ranked first, or null when they
-- aren't a member.
create or replace function better_supabase.organization_member_roles(organization uuid, member uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select (
    select array_agg(r."role" order by array_position(array['owner', 'admin', 'member', 'viewer']::text[], r."role"), r."role")
    from "better_supabase"."membership_roles" r where r."organization_id" = m."organization_id" and r."user_id" = m."user_id"
  )
  from "better_supabase"."memberships" m where m."organization_id" = organization_member_roles.organization and m."user_id" = organization_member_roles.member and m."disabled_at" is null
$$;
revoke execute on function better_supabase.organization_member_roles(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.organization_member_roles(uuid, uuid) to service_role;

create policy bsb_memberships_read on "better_supabase"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

create policy bsb_membership_roles_read on "better_supabase"."membership_roles"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to anon, authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to anon, authenticated, service_role;
grant execute on function better_supabase.organization_member_role(uuid, uuid) to service_role;

-- The memberships claim. `claimFormat: 'array'` (the default) is
-- [{ scope, id, roles }]; `'map'` is { [tenant id]: role }; `'summary'`
-- is { form, roles, tenants } with a role index per tenant, or a sorted
-- array of indexes when a member holds several roles. When an
-- authorization provider's hook writes this claim, use its hook instead.
-- Otherwise call it from your custom access token hook:
--   return jsonb_set(event, '{claims,memberships}',
--     better_supabase.membership_claims((event ->> 'user_id')::uuid));
-- Disabled users and tenants (blocks.permissions.disabled) are left out.
create or replace function better_supabase.membership_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'scope', 'tenant',
      'id', m."organization_id",
      'roles', (select coalesce(jsonb_agg(r."role" order by r."role"), '[]'::jsonb) from "better_supabase"."membership_roles" r where r."organization_id" = m."organization_id" and r."user_id" = m."user_id")
    ) order by m."created_at", m."organization_id"), '[]'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;
reset check_function_bodies;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."memberships" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."memberships" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."memberships" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."memberships" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:01807a57c2608444bd77875fbb02e8a50d3a9202f1a6aa1092a050e20162d87b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Every membership holds its primary role in the role set.
insert into "better_supabase"."membership_roles" ("organization_id", "user_id", "role")
select m."organization_id", m."user_id", m."role"::text from "better_supabase"."memberships" m
where m."role" is not null
on conflict ("organization_id", "user_id", "role") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== permissions
-- better-supabase module: permissions
-- @bsb-block permissions@1 managed
-- @bsb-hash sha256:095ad04e28b96d3c9075d54c058be52af6baa4d4869836c524d8a3ed66141b3c
-- can(), tenant_ids_with() and is_platform(): one permission contract for policies and SQL modules, over a roles list, a role and permission catalog, an authorization provider or the app's own functions (blocks.permissions.model).
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

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

-- True for a user's own session and for no token at all. False for an API
-- key (api_key), an OAuth client (client_id) and an act chain (an agent, a
-- delegation, support or impersonation).
create or replace function better_supabase.interactive_session()
returns boolean
language sql
stable
set search_path = ''
as $$
  select auth.jwt() is null
    or (auth.jwt() -> 'api_key' is null
      and coalesce(auth.jwt() ->> 'client_id', '') = ''
      and auth.jwt() -> 'act' is null)
$$;

-- The permission keys only a signed-in user gets (the built-in
-- interactive-only operations, authorization.delegation.interactiveOnly and
-- blocks.permissions.interactiveOnly): cap_allows refuses them to every
-- other session, whatever its scopes.
create or replace function better_supabase.interactive_only(permission text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(permission = any (array['organization.delete', 'organization.transfer_ownership', 'platform.invite']::text[]), false)
$$;

-- The roles only a signed-in user grants or takes away: the organization
-- owner role. can_assign refuses them to every other session.
create or replace function better_supabase.interactive_only_role(role text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(role = 'owner', false)
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

-- False when the token is narrower than the permission: an interactive-only
-- key outside a user's own session, a permission cap (bsb_permission_cap)
-- without the key, an API key (api_key) or a delegated token whose scopes
-- don't map to it. An API key without scopes holds no permission. True
-- for every other token, the service role included.
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
    when better_supabase.interactive_only(cap_allows.permission)
      and not better_supabase.interactive_session() then false
    when jsonb_typeof(cap) = 'array'
      and not exists (
        select 1 from jsonb_array_elements_text(cap) c(key)
        where better_supabase.permission_matches(c.key, cap_allows.permission)
      ) then false
    when jsonb_typeof(jwt -> 'api_key') = 'object' then exists (
      select 1
      from jsonb_array_elements_text(case jsonb_typeof(jwt -> 'api_key' -> 'scopes')
          when 'array' then jwt -> 'api_key' -> 'scopes'
          else '[]'::jsonb
        end) s(scope)
      cross join lateral unnest(better_supabase.scope_permissions(s.scope)) k(key)
      where better_supabase.permission_matches(k.key, cap_allows.permission)
    )
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
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.read' then 'members.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
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
    when 'admin' then array['organization.read', 'organization.update', 'members.*', 'audit.read', 'audit.revert', 'webhooks.*', 'notifications.*', 'billing.*', 'api_keys.*', 'settings.*', 'usage.*', 'timeline.read', 'attachments.*', 'data_lifecycle.export', 'onboarding.*', 'inbox.*', 'ai_chat.*', 'agents.*', 'ai_files.*', 'ai_keys.*', 'ai_schedules.*', 'connectors.*', 'knowledge.*', 'memory.*', 'tags.*', 'teams.*', 'subjects.*', 'custom_fields.*', 'field_encryption.*', 'share_links.*', 'reminders.*', 'imports.*', 'saved_views.*', 'relations.*', 'bulk_actions.*', 'search.*', 'metrics.*', 'calendar.*', 'bookings.*', 'versions.*', 'trash.*', 'reactions.*', 'approvals.*', 'access_requests.*', 'documents.*', 'drive.*', 'forms.*', 'signatures.*', 'templates.*', 'time_entries.*', 'service_accounts.*', 'pipelines.*', 'option_sets.*', 'contacts.*', 'activities.*', 'deals.*', 'tasks.*', 'quotes.*', 'invoices.*', 'sla.*', 'goals.*', 'hiring.*', 'employees.*', 'collections.*', 'messages.*', 'channels.*', 'mail_sync.*', 'legal_entities.*', 'document_templates.*', 'segments.*', 'assignment.*', 'enrichment.*', 'forecasts.*', 'field_history.*', 'domains.*', 'automations.*', 'reviews.*', 'leave.*', 'ledger.*', 'assets.*', 'scores.*', 'moderation.*', 'enrollments.*', 'guests.*', 'passes.*', 'billable_time.*', 'leases.*', 'expenses.*', 'donations.*', 'dispatch.*', 'shipments.*', 'contracts.*', 'compliance.*', 'acknowledgements.*', 'incidents.*', 'courses.*', 'sequences.*', 'posts.*', 'content.*', 'qualifications.*', 'risks.*', 'advisories.*', 'shifts.*', 'consents.*', 'waitlist.invite', 'accounting.*', 'observations.*', 'medications.*', 'care_plans.*', 'cases.*', 'inspections.*', 'meetings.*', 'maintenance.*', 'dam.*', 'lims.*', 'appraisals.*', 'warehouse.*', 'rfqs.*', 'tills.*', 'periods.*', 'deadlines.*', 'commissions.*', 'referrals.*', 'agent_checkout.*', 'clinical_decision_support.*', 'e_prescribing.*', 'manufacturing.*', 'banking.*', 'tax.*', 'funding.*', 'payroll_export.*', 'warranty.*', 'numbering.*']::text[]
    when 'member' then array['organization.read', 'members.read', 'notifications.read', 'api_keys.own', 'settings.read', 'timeline.read', 'attachments.read', 'attachments.upload', 'onboarding.read', 'inbox.read', 'inbox.reply', 'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'agents.read', 'agents.write', 'agents.publish', 'ai_files.upload', 'ai_keys.use', 'ai_schedules.write', 'connectors.read', 'connectors.use', 'knowledge.read', 'knowledge.write', 'memory.read', 'custom_fields.read', 'teams.read', 'tags.read', 'tags.apply', 'share_links.read', 'reminders.read', 'saved_views.read', 'relations.read', 'bulk_actions.run', 'search.read', 'metrics.read', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'versions.restore', 'trash.read', 'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read', 'approvals.request', 'access_requests.create', 'documents.read', 'documents.write', 'documents.suggest', 'drive.read', 'drive.create', 'forms.read', 'forms.submit', 'signatures.read', 'signatures.request', 'templates.read', 'templates.apply', 'time_entries.track', 'leave.request', 'pipelines.read', 'option_sets.read', 'contacts.read', 'contacts.write', 'activities.read', 'activities.write', 'deals.read', 'deals.write', 'tasks.read', 'tasks.write', 'quotes.read', 'quotes.write', 'invoices.read', 'sla.read', 'goals.read', 'employees.read', 'collections.read', 'collections.write', 'domains.read', 'automations.read', 'assets.read', 'scores.read', 'moderation.report', 'enrollments.read', 'leases.maintain', 'expenses.submit', 'dispatch.read', 'dispatch.work', 'shipments.read', 'contracts.read', 'contracts.write', 'compliance.read', 'compliance.collect', 'acknowledgements.acknowledge', 'incidents.read', 'incidents.write', 'courses.read', 'sequences.read', 'sequences.enroll', 'posts.read', 'posts.write', 'content.read', 'content.write', 'shifts.read', 'shifts.request', 'messages.read', 'messages.send', 'channels.create', 'mail_sync.read', 'legal_entities.read', 'document_templates.read', 'mail_sync.connect', 'mail_sync.send', 'segments.read', 'assignment.read', 'enrichment.read', 'forecasts.read', 'field_history.read', 'risks.read', 'advisories.read', 'observations.read', 'observations.record', 'care_plans.read', 'cases.read', 'cases.create', 'manufacturing.read', 'manufacturing.produce', 'banking.read', 'banking.reconcile', 'tax.read', 'funding.read', 'funding.register', 'warranty.read', 'warranty.write']::text[]
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
        and exists (select 1 from "better_supabase"."membership_roles" mr where mr."organization_id" = m."organization_id" and mr."user_id" = m."user_id" and better_supabase.role_grants(mr."role", member_can.permission))
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
        and exists (select 1 from "better_supabase"."membership_roles" mr where mr."organization_id" = m."organization_id" and mr."user_id" = m."user_id" and better_supabase.role_grants(mr."role", member_can_while_deleting.permission))
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
      select array_agg(distinct k.key order by k.key) from "better_supabase"."memberships" m
      join "better_supabase"."membership_roles" mr on mr."organization_id" = m."organization_id" and mr."user_id" = m."user_id"
      cross join unnest(better_supabase.role_permissions(mr."role")) k(key)
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
    and exists (select 1 from "better_supabase"."membership_roles" mr where mr."organization_id" = m."organization_id" and mr."user_id" = m."user_id" and better_supabase.role_grants(mr."role", tenant_ids_with.permission))
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
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role' or ((better_supabase.interactive_session() or not better_supabase.interactive_only_role(can_assign.role)) and better_supabase.can_assign_as(auth.uid(), can_assign.tenant, can_assign.role))
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
cost 1000
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
$$;-- Compact permissions for the caller: keys once, then a bitset per tenant.
create or replace function better_supabase.permission_bitset(all_keys text[], held text[])
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  width integer := ceil(coalesce(cardinality(all_keys), 0) / 8.0);
  bytes bytea;
  i integer;
  slot integer;
  value integer;
begin
  if width < 1 then
    return '';
  end if;
  bytes := decode(repeat('00', width), 'hex');
  if held is null then
    return translate(rtrim(encode(bytes, 'base64'), '='), E'+/\n', '-_');
  end if;
  for i in 1 .. coalesce(cardinality(all_keys), 0) loop
    if all_keys[i] = any (held) then
      slot := (i - 1) / 8;
      value := get_byte(bytes, slot) | (1 << ((i - 1) % 8));
      bytes := set_byte(bytes, slot, value);
    end if;
  end loop;
  return translate(rtrim(encode(bytes, 'base64'), '='), E'+/\n', '-_');
end;
$$;

revoke execute on function better_supabase.permission_bitset(text[], text[]) from public, anon, authenticated;

create or replace function better_supabase.bootstrap_permissions()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with keys as (
    select coalesce(array_agg(distinct key order by key), '{}'::text[]) as keys
    from better_supabase.member_organization_ids(null) as tenant(id),
      lateral unnest(better_supabase.member_permissions(auth.uid(), tenant.id)) as key
    where auth.uid() is not null
  )
  select case
    when auth.uid() is null then jsonb_build_object(
      'apiVersion', 1, 'form', 'compact', 'keys', '[]'::jsonb, 'tenants', '{}'::jsonb
    )
    else jsonb_build_object(
      'apiVersion', 1,
      'form', 'compact',
      'keys', to_jsonb(keys.keys),
      'tenants', coalesce((
        select jsonb_object_agg(
          tenant.id::text,
          better_supabase.permission_bitset(
            keys.keys,
            better_supabase.member_permissions(auth.uid(), tenant.id)
          )
        )
        from better_supabase.member_organization_ids(null) as tenant(id)
      ), '{}'::jsonb)
    )
  end
  from keys
$$;

revoke execute on function better_supabase.bootstrap_permissions() from public, anon;
grant execute on function better_supabase.bootstrap_permissions() to authenticated;

revoke execute on function better_supabase.permission_matches(text, text) from public;
grant execute on function better_supabase.permission_matches(text, text) to anon, authenticated, service_role;
revoke execute on function better_supabase.scope_permissions(text) from public;
grant execute on function better_supabase.scope_permissions(text) to anon, authenticated, service_role;
revoke execute on function better_supabase.cap_allows(text) from public;
grant execute on function better_supabase.cap_allows(text) to anon, authenticated, service_role;
revoke execute on function better_supabase.interactive_session() from public;
grant execute on function better_supabase.interactive_session() to anon, authenticated, service_role;
revoke execute on function better_supabase.interactive_only(text) from public;
grant execute on function better_supabase.interactive_only(text) to anon, authenticated, service_role;
revoke execute on function better_supabase.interactive_only_role(text) from public;
grant execute on function better_supabase.interactive_only_role(text) to anon, authenticated, service_role;
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

-- ==== organizations
-- better-supabase module: organizations
-- @bsb-block organizations@1 managed
-- @bsb-hash sha256:6b4823a301a634d7d5b0a11ab43ac7cefe1c6ad6ea0719b53b5ec0309da69335
-- create_organization(attrs) with slug rules and an after-create hook, a deferred owner check, an assignment ceiling, and member functions (role change, remove, leave, transfer ownership) on the access contract.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."organizations" (
  "id" uuid primary key default gen_random_uuid(),
  "name" text not null constraint bsb_organizations_name_check check (length(btrim("name")) > 0),
  "slug" text not null,
  "created_by" uuid references auth.users (id) on delete set null,
  "created_at" timestamptz not null default now(),
  "disabled_at" timestamptz,
  "deleted_at" timestamptz
);
create unique index organizations_slug_idx on "better_supabase"."organizations" (lower("slug"::text)) where "deleted_at" is null;
create index organizations_created_by_idx on "better_supabase"."organizations" ("created_by");
alter table "better_supabase"."organizations" add column "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "better_supabase"."organizations"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."organizations" enable row level security;
revoke all on "better_supabase"."organizations" from public, anon, authenticated;
grant select on "better_supabase"."organizations" to authenticated;
grant all on "better_supabase"."organizations" to service_role;
create policy bsb_organizations_read on "better_supabase"."organizations"
  for select to authenticated
  using ("id" in (select better_supabase.member_organization_ids()));

alter table "better_supabase"."memberships" add constraint "memberships_organization_fkey"
  foreign key ("organization_id") references "better_supabase"."organizations" ("id") on delete cascade;
alter table "better_supabase"."invitations" add constraint "invitations_organization_fkey"
  foreign key ("tenant_id") references "better_supabase"."organizations" ("id") on delete cascade;

-- Why a slug can't be used, or null: 'invalid' (length and pattern from
-- blocks.organizations.options), 'reserved' or 'taken'. except_organization skips the
-- organization being renamed.
create or replace function "better_supabase"."organization_slug_problem"(value text, except_organization uuid default null)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when value is null then null
    when length(value) < 2 or length(value) > 48 or value !~ '^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$' then 'invalid'
    when false then 'reserved'
    when exists (
      select 1 from "better_supabase"."organizations" o
      where lower(o."slug"::text) = lower(value) and o."deleted_at" is null
        and o."id" is distinct from except_organization
    ) then 'taken'
  end
$$;
revoke execute on function "better_supabase"."organization_slug_problem"(text, uuid) from public, anon;
grant execute on function "better_supabase"."organization_slug_problem"(text, uuid) to authenticated, service_role;

-- Creates an organization from attrs (its name, slug and the columns in
-- blocks.organizations.options.attributes) and makes the caller its owner. The
-- service role passes the owner as attrs.owner_id.
create or replace function "better_supabase"."create_organization"(attrs jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  owner uuid := case when service then nullif(attrs ->> 'owner_id', '')::uuid else auth.uid() end;
  organization uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if owner is null then
    raise exception 'An organization needs an owner' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if better_supabase.user_disabled(owner) then
    raise exception 'The user is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  case "better_supabase"."organization_slug_problem"(coalesce(attrs ->> 'slug', ''), null)
    when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
    when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
    when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
    else null;
  end case;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_organization_create"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, owner;
    end if;
  end;
  insert into "better_supabase"."organizations" ("name", "slug", "created_by")
  select r."name", r."slug", owner
  from jsonb_populate_record(null::"better_supabase"."organizations", attrs) r
  returning "id" into organization;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (organization, owner, 'owner');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_create"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using organization, owner;
    end if;
  end;
  null;
  return organization;
end;
$$;

-- Updates the name, slug and attribute columns present in attrs.
create or replace function "better_supabase"."update_organization"(organization uuid, attrs jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.update'), false) then
    raise exception 'Not allowed to update the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if attrs ? 'slug' then
    case "better_supabase"."organization_slug_problem"(coalesce(attrs ->> 'slug', ''), organization)
      when 'invalid' then raise exception 'Invalid slug "%"', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_INVALID';
      when 'reserved' then raise exception 'The slug "%" is reserved', attrs ->> 'slug' using errcode = '23514', hint = 'ORGANIZATION_SLUG_RESERVED';
      when 'taken' then raise exception 'The slug "%" is taken', attrs ->> 'slug' using errcode = '23505', hint = 'ORGANIZATION_SLUG_TAKEN';
      else null;
    end case;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  update "better_supabase"."organizations" o
  set "name" = case when attrs ? 'name' then r."name" else o."name" end,
    "slug" = case when attrs ? 'slug' then r."slug" else o."slug" end
  from jsonb_populate_record(null::"better_supabase"."organizations", attrs) r
  where o."id" = organization;
  if not found then
    raise exception 'No organization %', organization using errcode = 'P0002', hint = 'ORGANIZATION_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_organization_update"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using organization, attrs;
    end if;
  end;
  null;
  return true;
end;
$$;

-- Deletes an organization (blocks.organizations.options.deleteMode: hard, with its memberships).
create or replace function "better_supabase"."delete_organization"(organization uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.delete'), false) then
    raise exception 'Not allowed to delete the organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  delete from "better_supabase"."organizations" where "id" = organization;
  if not found then
    return false;
  end if;
  delete from "better_supabase"."memberships" where "organization_id" = organization;
  null;
  return true;
end;
$$;

-- Checked at commit, so one transaction can promote one owner and demote
-- another. An organization may have several owners.
create or replace function "better_supabase"."ensure_organization_owner"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The row lock serializes concurrent demotions and leaves, so two
  -- transactions can't each remove a different last owner.
  perform 1 from "better_supabase"."organizations" o where o."id" = old."organization_id" for update;
  if found and not exists (
      select 1 from "better_supabase"."memberships" m where m."organization_id" = old."organization_id" and exists (select 1 from "better_supabase"."membership_roles" mr where mr."organization_id" = m."organization_id" and mr."user_id" = m."user_id" and mr."role" = 'owner') and m."disabled_at" is null
    ) then
    raise exception 'An organization needs an owner' using errcode = '23514', hint = 'ORGANIZATION_OWNER_REQUIRED';
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."ensure_organization_owner"() from public, anon, authenticated;
create constraint trigger "bsb_organization_owner" after update of "role", "organization_id", "disabled_at" or delete on "better_supabase"."memberships"
  deferrable initially deferred
  for each row execute function "better_supabase"."ensure_organization_owner"();

-- No client grants a role above their own permissions (can_assign), demotes
-- someone above them, or changes their own role. Only writes made as anon or
-- authenticated are checked: the service role, direct admin connections and
-- security definer functions (the module's own and the app's, which check
-- their own ceilings) pass.
-- The checks, as the module's owner, so the client needs no rights on the
-- roles tables. It only raises, so a direct call reveals nothing.
create or replace function "better_supabase"."guard_membership_role"(target_tenant uuid, target_member uuid, target_role text, previous_tenant uuid, previous_role text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if target_member = auth.uid() then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(target_tenant, target_role::text)
    or (previous_tenant is not null and not better_supabase.can_assign(previous_tenant, previous_role::text)) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
end;
$$;
revoke execute on function "better_supabase"."guard_membership_role"(uuid, uuid, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."guard_membership_role"(uuid, uuid, text, uuid, text) to authenticated, service_role;

-- Security invoker, so current_user is the role that wrote the row.
create or replace function "better_supabase"."guard_membership"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not (current_user in ('anon', 'authenticated')) then
    return new;
  end if;
  if tg_op = 'UPDATE' and new."role" is not distinct from old."role" and new."disabled_at" is not distinct from old."disabled_at" then
    return new;
  end if;
  perform "better_supabase"."guard_membership_role"(
    new."organization_id", new."user_id", new."role"::text,
    case when tg_op = 'UPDATE' then old."organization_id" end,
    case when tg_op = 'UPDATE' then old."role"::text end
  );
  return new;
end;
$$;
create trigger "bsb_organization_role_guard" before insert or update on "better_supabase"."memberships"
  for each row execute function "better_supabase"."guard_membership"();
revoke execute on function "better_supabase"."guard_membership"() from public, anon, authenticated;

-- Errors carry a code in the hint: ORGANIZATION_FORBIDDEN, ORGANIZATION_DISABLED, ORGANIZATION_NOT_MEMBER,
-- ORGANIZATION_SELF, ORGANIZATION_SELF_ROLE, ORGANIZATION_ROLE_CEILING, ORGANIZATION_ROLE_UNKNOWN, ORGANIZATION_OWNER_REQUIRED,
-- ORGANIZATION_ROLE_LAST.
create or replace function "better_supabase"."update_member_role"(organization uuid, member uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  previous text;
  previous_assignable text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.update_role'), false)) then
    raise exception 'Not allowed to change roles' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "better_supabase"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (role = any (array['owner', 'admin', 'member', 'viewer']::text[])) then
    raise exception 'Unknown role %', role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  select m."role", m."role"::text into previous, previous_assignable
  from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  -- Checked here whatever blocks.organizations.options.assignmentGuard
  -- says: a guard that checks only client writes never sees this function's.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and coalesce(member = auth.uid(), false) then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(organization, previous_assignable)
    or not better_supabase.can_assign(organization, (role)::text) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  update "better_supabase"."memberships" set "role" = role
  where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'role';
    end if;
  end;
  null;
  return true;
end;
$$;

create or replace function "better_supabase"."remove_member"(organization uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  current_role_value text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if member = auth.uid() then
    raise exception 'Leave the organization instead' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false)) then
    raise exception 'Not allowed to remove members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  select m."role"::text into current_role_value from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  delete from "better_supabase"."memberships" where "organization_id" = organization and "user_id" = member;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'removed';
    end if;
  end;
  null;
  return true;
end;
$$;

create or replace function "better_supabase"."leave_organization"(organization uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."memberships" where "organization_id" = organization and "user_id" = me;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, me, 'left';
    end if;
  end;
  null;
  return true;
end;
$$;

-- Makes new_owner an owner in one transaction; a calling owner becomes
-- former_role (blocks.organizations.options.formerOwnerRole).
create or replace function "better_supabase"."transfer_ownership"(organization uuid, new_owner uuid, former_role text default 'admin')
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'organization.transfer_ownership'), false)) then
    raise exception 'Not allowed to transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  -- Only an owner hands ownership on, so the permission alone can't make its
  -- holder an owner.
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and not exists (
    select 1 from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = me and exists (select 1 from "better_supabase"."membership_roles" mr where mr."organization_id" = m."organization_id" and mr."user_id" = m."user_id" and mr."role" = 'owner')
  ) then
    raise exception 'Only an owner can transfer ownership' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "better_supabase"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (former_role = any (array['owner', 'admin', 'member', 'viewer']::text[])) then
    raise exception 'Unknown role %', former_role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = new_owner) then
    raise exception 'The new owner must be a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if better_supabase.user_disabled(new_owner) then
    raise exception 'The new owner is disabled' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = new_owner and m."disabled_at" is not null) then
    raise exception 'The new owner is suspended' using errcode = '42501', hint = 'ORGANIZATION_MEMBER_SUSPENDED';
  end if;
  insert into "better_supabase"."membership_roles" ("organization_id", "user_id", "role") values (organization, new_owner, 'owner')
  on conflict do nothing;
  if me is not null and me <> new_owner and exists (
    select 1 from "better_supabase"."membership_roles" r where r."organization_id" = organization and r."user_id" = me and r."role" = 'owner'
  ) then
    insert into "better_supabase"."membership_roles" ("organization_id", "user_id", "role") values (organization, me, former_role)
    on conflict do nothing;
    delete from "better_supabase"."membership_roles" r where r."organization_id" = organization and r."user_id" = me and r."role" = 'owner';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, new_owner, 'owner';
    end if;
  end;
  null;
  return true;
end;
$$;


-- blocks.memberships.options.roles.many: add or remove one of a member's
-- roles. The membership's role column follows the highest-ranked one left.
create or replace function "better_supabase"."add_member_role"(organization uuid, member uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.update_role'), false)) then
    raise exception 'Not allowed to change roles' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "better_supabase"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not (role = any (array['owner', 'admin', 'member', 'viewer']::text[])) then
    raise exception 'Unknown role %', role using errcode = '22023', hint = 'ORGANIZATION_ROLE_UNKNOWN';
  end if;
  if not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = member) then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and coalesce(member = auth.uid(), false) then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(organization, role) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  insert into "better_supabase"."membership_roles" ("organization_id", "user_id", "role") values (organization, member, role)
  on conflict do nothing;
  if not found then
    return false;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'role';
    end if;
  end;
  null;
  return true;
end;
$$;

create or replace function "better_supabase"."remove_member_role"(organization uuid, member uuid, role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.update_role'), false)) then
    raise exception 'Not allowed to change roles' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "better_supabase"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  if not exists (select 1 from "better_supabase"."membership_roles" r where r."organization_id" = organization and r."user_id" = member and r."role" = role) then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and coalesce(member = auth.uid(), false) then
    raise exception 'You cannot change your own role' using errcode = '42501', hint = 'ORGANIZATION_SELF_ROLE';
  end if;
  if not better_supabase.can_assign(organization, role) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  if not exists (select 1 from "better_supabase"."membership_roles" r where r."organization_id" = organization and r."user_id" = member and r."role" <> role) then
    raise exception 'A member keeps at least one role; remove the member instead' using errcode = '22023', hint = 'ORGANIZATION_ROLE_LAST';
  end if;
  if role = 'owner' and not exists (
    select 1 from "better_supabase"."membership_roles" r where r."organization_id" = organization and r."user_id" <> member and r."role" = 'owner'
  ) then
    raise exception 'An organization keeps at least one owner' using errcode = '42501', hint = 'ORGANIZATION_OWNER_REQUIRED';
  end if;
  delete from "better_supabase"."membership_roles" r where r."organization_id" = organization and r."user_id" = member and r."role" = role;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'role';
    end if;
  end;
  null;
  return true;
end;
$$;

-- Records that the caller opened the organization (the last_used_at column of
-- memberships, when it has one), for "recent organizations" lists.
create or replace function "better_supabase"."mark_used"(organization uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."memberships" set "last_used_at" = now()
  where "organization_id" = organization and "user_id" = auth.uid();
  return found;
end;
$$;

-- The role change for many members in one call (ADR 0853). It runs as the
-- caller: update_member_role is the security definer and does the checking,
-- once per distinct member in its own subtransaction, so every check and event
-- of the single call still runs. Returns { succeeded: [id], failed: [{ id,
-- code, message }] }; more than 500 members fail with BULK_TOO_MANY.
create or replace function "better_supabase"."update_member_roles"(organization uuid, members uuid[], role text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  one uuid;
  succeeded jsonb := '[]'::jsonb;
  failed jsonb := '[]'::jsonb;
  failure_hint text;
  failure_message text;
begin
  if coalesce(cardinality(members), 0) > 500 then
    raise exception 'A bulk call takes at most 500 members' using errcode = '22023', hint = 'BULK_TOO_MANY';
  end if;
  for one in select distinct m from unnest(members) m loop
    begin
      perform "better_supabase"."update_member_role"(organization, one, role);
      succeeded := succeeded || to_jsonb(one::text);
    exception when others then
      get stacked diagnostics failure_hint = pg_exception_hint, failure_message = message_text;
      failed := failed || jsonb_build_object('id', one::text, 'code', failure_hint, 'message', failure_message);
    end;
  end loop;
  return jsonb_build_object('succeeded', succeeded, 'failed', failed);
end;
$$;

create or replace function "better_supabase"."suspend_member"(organization uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  current_role_value text;
  is_owner boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if member = auth.uid() then
    raise exception 'You cannot suspend yourself' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false)) then
    raise exception 'Not allowed to suspend members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "better_supabase"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  perform 1 from "better_supabase"."organizations" o where o."id" = organization for update;
  select m."role"::text, exists (select 1 from "better_supabase"."membership_roles" mr where mr."organization_id" = m."organization_id" and mr."user_id" = m."user_id" and mr."role" = 'owner') into current_role_value, is_owner
  from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  if is_owner and not exists (
    select 1 from "better_supabase"."memberships" o
    where o."organization_id" = organization and o."user_id" <> member and exists (select 1 from "better_supabase"."membership_roles" mr where mr."organization_id" = o."organization_id" and mr."user_id" = o."user_id" and mr."role" = 'owner') and o."disabled_at" is null
  ) then
    raise exception 'An organization needs an owner' using errcode = '23514', hint = 'ORGANIZATION_OWNER_REQUIRED';
  end if;
  update "better_supabase"."memberships" set "disabled_at" = now()
  where "organization_id" = organization and "user_id" = member and "disabled_at" is null;
  if not found then
    return false;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'suspended';
    end if;
  end;
  null;
  return true;
end;
$$;

create or replace function "better_supabase"."resume_member"(organization uuid, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  current_role_value text;
  is_owner boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if member = auth.uid() then
    raise exception 'You cannot resume yourself' using errcode = '22023', hint = 'ORGANIZATION_SELF';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), organization, 'members.remove'), false)) then
    raise exception 'Not allowed to resume members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if not (exists (select 1 from "better_supabase"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  perform 1 from "better_supabase"."organizations" o where o."id" = organization for update;
  select m."role"::text, exists (select 1 from "better_supabase"."membership_roles" mr where mr."organization_id" = m."organization_id" and mr."user_id" = m."user_id" and mr."role" = 'owner') into current_role_value, is_owner
  from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = member;
  if not found then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not better_supabase.can_assign(organization, current_role_value) then
    raise exception 'That member''s role is above your own' using errcode = '42501', hint = 'ORGANIZATION_ROLE_CEILING';
  end if;
  update "better_supabase"."memberships" set "disabled_at" = null
  where "organization_id" = organization and "user_id" = member and "disabled_at" is not null;
  if not found then
    return false;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_member_change"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using organization, member, 'resumed';
    end if;
  end;
  null;
  return true;
end;
$$;

-- Makes organization the caller's active organization (blocks.permissions.activeTenant).
create or replace function "better_supabase"."switch_organization"(organization uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null or not exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = organization and m."user_id" = me) then
    raise exception 'Not a member' using errcode = 'P0002', hint = 'ORGANIZATION_NOT_MEMBER';
  end if;
  if not (exists (select 1 from "better_supabase"."organizations" o where o."id" = organization and o."deleted_at" is null and o."disabled_at" is null) and not better_supabase.tenant_disabled(organization)) then
    raise exception 'The organization is unavailable' using errcode = '42501', hint = 'ORGANIZATION_DISABLED';
  end if;
  -- The server's tenant resolver picks the tenant per request.
  update "better_supabase"."memberships" set "last_used_at" = now() where "organization_id" = organization and "user_id" = me;
  null;
  return jsonb_build_object('organization_id', organization, 'refresh', false);
end;
$$;
create or replace function "better_supabase"."list_my_organizations"()
returns table (
  id uuid,
  name text,
  slug text,
  role text,
  roles text[],
  disabled_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select o."id", o."name", o."slug", m."role"::text, array(select r."role" from "better_supabase"."membership_roles" r where r."organization_id" = m."organization_id" and r."user_id" = m."user_id" order by r."role"), m."disabled_at"
  from "better_supabase"."memberships" m
  join "better_supabase"."organizations" o on o."id" = m."organization_id"
  where m."user_id" = (select auth.uid()) and o."deleted_at" is null and o."disabled_at" is null
    and not better_supabase.tenant_disabled(o."id")
  order by o."name"
$$;
create or replace function "better_supabase"."list_members"(organization uuid)
returns table (user_id uuid, role text, roles text[], disabled_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, 'members.read'), false) then
    raise exception 'Not allowed to list members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return query
  select m."user_id", m."role"::text, array(select r."role" from "better_supabase"."membership_roles" r where r."organization_id" = m."organization_id" and r."user_id" = m."user_id" order by r."role"), m."disabled_at"
  from "better_supabase"."memberships" m
  where m."organization_id" = organization
  order by m."user_id";
end;
$$;

create or replace function "better_supabase"."list_organization_invitations"(organization uuid)
returns table (
  id uuid,
  email text,
  role text,
  expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, 'members.invite'), false) then
    raise exception 'Not allowed to list invitations' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return query
  select i."id", i."email", i."role"::text, i."expires_at"
  from "better_supabase"."invitations" i
  where i."tenant_id" = organization and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null and i."expires_at" >= now()
  order by i."expires_at" desc;
end;
$$;

-- The open invitations of an organization as a keyset page, latest expiry
-- first. filters is { role (a value or a list), search, sort, direction, facet,
-- count, limit, after, offset, paged, total, totalCap } (ADR 0749, 0923).
create or replace function "better_supabase"."page_organization_invitations"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_organization_invitations.filters, '{}'::jsonb);
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
  if not coalesce(better_supabase.member_can((select auth.uid()), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to list invitations' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('role') then
      raise exception 'facet is one of role' using errcode = '22023', hint = 'INVITATION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'role' then (i."role"::text)::text end) as v
      from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
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
      select 1 from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('expiresAt', 'email') then
    raise exception 'sort is one of expiresAt, email' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', i."id", 'email', i."email", 'role', i."role"::text, 'expiresAt', i."expires_at") as j, jsonb_build_array((coalesce(i."expires_at", 'infinity'::timestamptz))::text, (i."id")::text) as k
    from (
      select * from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
        and (v_after is null or (coalesce(i."expires_at", 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(i."expires_at", 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(i."expires_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and i."id" < (v_after ->> 1)::uuid))))
      order by coalesce(i."expires_at", 'infinity'::timestamptz) asc, i."id" desc
      limit v_limit + 1 offset v_offset
    ) i
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', i."id", 'email', i."email", 'role', i."role"::text, 'expiresAt', i."expires_at") as j, jsonb_build_array((coalesce(i."expires_at", 'infinity'::timestamptz))::text, (i."id")::text) as k
    from (
      select * from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
        and (v_after is null or (coalesce(i."expires_at", 'infinity'::timestamptz), i."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(i."expires_at", 'infinity'::timestamptz) desc, i."id" desc
      limit v_limit + 1 offset v_offset
    ) i
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', i."id", 'email', i."email", 'role', i."role"::text, 'expiresAt', i."expires_at") as j, jsonb_build_array((coalesce(i."expires_at", 'infinity'::timestamptz))::text, (i."id")::text) as k
    from (
      select * from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
        and (v_after is null or (coalesce(i."expires_at", 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(i."expires_at", 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(i."expires_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and i."id" < (v_after ->> 1)::uuid))))
      order by coalesce(i."expires_at", 'infinity'::timestamptz) asc, i."id" desc
      limit v_limit + 1 offset v_offset
    ) i
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', i."id", 'email', i."email", 'role', i."role"::text, 'expiresAt', i."expires_at") as j, jsonb_build_array((coalesce(i."expires_at", 'infinity'::timestamptz))::text, (i."id")::text) as k
    from (
      select * from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
        and (v_after is null or (coalesce(i."expires_at", 'infinity'::timestamptz), i."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(i."expires_at", 'infinity'::timestamptz) desc, i."id" desc
      limit v_limit + 1 offset v_offset
    ) i
  ) p;
  elsif v_sort = 'email' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', i."id", 'email', i."email", 'role', i."role"::text, 'expiresAt', i."expires_at") as j, jsonb_build_array((lower(i."email"))::text, (i."id")::text) as k
    from (
      select * from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
        and (v_after is null or (lower(i."email"), i."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(i."email") asc, i."id" asc
      limit v_limit + 1 offset v_offset
    ) i
  ) p;
  elsif v_sort = 'email' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INVITATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', i."id", 'email', i."email", 'role', i."role"::text, 'expiresAt', i."expires_at") as j, jsonb_build_array((lower(i."email"))::text, (i."id")::text) as k
    from (
      select * from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
        and (v_after is null or (lower(i."email") <= (v_after ->> 0)::text and ((lower(i."email") < (v_after ->> 0)::text) or (lower(i."email") = (v_after ->> 0)::text and i."id" > (v_after ->> 1)::uuid))))
      order by lower(i."email") desc, i."id" asc
      limit v_limit + 1 offset v_offset
    ) i
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."invitations" i
      where i."tenant_id" = page_organization_invitations.tenant
        and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
        and i."expires_at" >= now()
        and (not (v_filters -> 'role' is not null and jsonb_typeof(v_filters -> 'role') <> 'null' and not (jsonb_typeof(v_filters -> 'role') = 'array' and jsonb_array_length(v_filters -> 'role') = 0)) or i."role"::text = any((case when jsonb_typeof(v_filters -> 'role') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'role')) else array[v_filters ->> 'role'] end)::text[]))
        and (v_search is null or i."email" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$$;

-- The organization page in one call. It runs as the caller and reads through
-- the listing functions, so the permissions to list members and invitations
-- apply. Seats come from billing_status and are null when the caller may not
-- read billing.
create or replace function "better_supabase"."organization_overview"(organization uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_org jsonb;
  v_seats integer;
begin
  select to_jsonb(o) into v_org
  from "better_supabase"."list_my_organizations"() o
  where o.id = organization_overview.organization;
  if v_org is null then
    raise exception 'Not a member of this organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  
  return jsonb_build_object(
    'id', v_org ->> 'id',
    'name', v_org ->> 'name',
    'slug', v_org -> 'slug',
    'role', v_org ->> 'role',
    'seats', v_seats,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', m.user_id, 'role', m.role,
        'roles', coalesce(to_jsonb(m) -> 'roles', jsonb_build_array(m.role)),
        'disabledAt', to_jsonb(m) -> 'disabled_at')
        order by m.user_id)
      from "better_supabase"."list_members"(organization_overview.organization) m
    ), '[]'::jsonb),
    'invitations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', i.id, 'email', i.email, 'role', i.role, 'expiresAt', to_jsonb(i) -> 'expires_at')
          order by i.email)
        from "better_supabase"."list_organization_invitations"(organization_overview.organization) i
      ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function "better_supabase"."create_organization"(jsonb) from public, anon;
grant execute on function "better_supabase"."create_organization"(jsonb) to authenticated, service_role;
revoke execute on function "better_supabase"."update_organization"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_organization"(uuid, jsonb) to authenticated, service_role;
revoke execute on function "better_supabase"."delete_organization"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_organization"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."update_member_role"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."update_member_role"(uuid, uuid, text) to authenticated, service_role;
revoke execute on function "better_supabase"."update_member_roles"(uuid, uuid[], text) from public, anon;
grant execute on function "better_supabase"."update_member_roles"(uuid, uuid[], text) to authenticated, service_role;
revoke execute on function "better_supabase"."remove_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_member"(uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."leave_organization"(uuid) from public, anon;
grant execute on function "better_supabase"."leave_organization"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."transfer_ownership"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."transfer_ownership"(uuid, uuid, text) to authenticated, service_role;
revoke execute on function "better_supabase"."mark_used"(uuid) from public, anon;
grant execute on function "better_supabase"."mark_used"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."switch_organization"(uuid) from public, anon;
grant execute on function "better_supabase"."switch_organization"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."list_my_organizations"() from public, anon;
grant execute on function "better_supabase"."list_my_organizations"() to authenticated, service_role;
revoke execute on function "better_supabase"."list_members"(uuid) from public, anon;
grant execute on function "better_supabase"."list_members"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."organization_overview"(uuid) from public, anon;
grant execute on function "better_supabase"."organization_overview"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."list_organization_invitations"(uuid) from public, anon;
grant execute on function "better_supabase"."list_organization_invitations"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."page_organization_invitations"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."page_organization_invitations"(uuid, jsonb) to authenticated, service_role;
revoke execute on function "better_supabase"."suspend_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."suspend_member"(uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."resume_member"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."resume_member"(uuid, uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."add_member_role"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."add_member_role"(uuid, uuid, text) to authenticated, service_role;
revoke execute on function "better_supabase"."remove_member_role"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."remove_member_role"(uuid, uuid, text) to authenticated, service_role;

create table "better_supabase"."organization_profiles" (
  "tenant_id" uuid primary key,
  "vat_id" text,
  "registration_id" text,
  "default_rate" numeric,
  "currency" text,
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."organization_profiles" enable row level security;
revoke all on "better_supabase"."organization_profiles" from public, anon, authenticated;
grant select on "better_supabase"."organization_profiles" to authenticated;
grant all on "better_supabase"."organization_profiles" to service_role;
create policy bsb_organization_profiles_read on "better_supabase"."organization_profiles"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

create table "better_supabase"."organization_payment_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "iban" text not null,
  "bic" text,
  "holder" text,
  "label" text,
  "is_primary" boolean not null default false,
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "iban")
);
create unique index organization_payment_accounts_primary_idx
  on "better_supabase"."organization_payment_accounts" ("tenant_id") where "is_primary";
alter table "better_supabase"."organization_payment_accounts" enable row level security;
revoke all on "better_supabase"."organization_payment_accounts" from public, anon, authenticated;
grant select on "better_supabase"."organization_payment_accounts" to authenticated;
grant all on "better_supabase"."organization_payment_accounts" to service_role;
create policy bsb_organization_payment_accounts_read on "better_supabase"."organization_payment_accounts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- The organization's VAT, registration, default rate, currency and payment
-- accounts. An IBAN matches on a repeat import. A missing value leaves the
-- stored one, and the stored primary account stays unless an account says
-- isPrimary. A VAT number that is only a country prefix is skipped.
create or replace function "better_supabase"."import_organization_profile"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_organization_profile.item -> 'data';
  v_tenant uuid := (import_organization_profile.item ->> 'tenant')::uuid;
  v_vat text := nullif(upper(btrim(v_data ->> 'vatId')), '');
  v_warnings jsonb := '[]'::jsonb;
  v_account jsonb;
  v_iban text;
  v_primary boolean;
  v_id uuid;
  v_updated timestamptz;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'an organization profile needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_vat ~ '^[A-Z]{2}$' then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_VAT_PREFIX', 'message', 'a VAT number that is only a country prefix was skipped'));
    v_vat := null;
  end if;
  insert into "better_supabase"."organization_profiles" ("tenant_id") values (v_tenant) on conflict ("tenant_id") do nothing;
  if exists (
    select 1 from "better_supabase"."organization_profiles" x
    where x."tenant_id" = v_tenant
      and (v_vat is null or x."vat_id" is not distinct from v_vat)
      and (v_data ->> 'registrationId' is null or x."registration_id" is not distinct from nullif(btrim(v_data ->> 'registrationId'), ''))
      and (v_data ->> 'defaultRate' is null or x."default_rate" is not distinct from (v_data ->> 'defaultRate')::numeric)
      and (v_data ->> 'currency' is null or x."currency" is not distinct from nullif(btrim(v_data ->> 'currency'), ''))
  ) then
    v_updated := (select x."updated_at" from "better_supabase"."organization_profiles" x where x."tenant_id" = v_tenant);
  else
    update "better_supabase"."organization_profiles" x set
      "vat_id" = coalesce(v_vat, x."vat_id"),
      "registration_id" = coalesce(nullif(btrim(v_data ->> 'registrationId'), ''), x."registration_id"),
      "default_rate" = coalesce((v_data ->> 'defaultRate')::numeric, x."default_rate"),
      "currency" = coalesce(nullif(btrim(v_data ->> 'currency'), ''), x."currency"),
      "updated_at" = now()
    where x."tenant_id" = v_tenant
    returning x."updated_at" into v_updated;
  end if;
  if jsonb_typeof(v_data -> 'accounts') = 'array' then
    for v_account in select value from jsonb_array_elements(v_data -> 'accounts') loop
      v_iban := upper(regexp_replace(coalesce(v_account ->> 'iban', ''), '\s', '', 'g'));
      if not better_supabase.validate_iban(v_iban) then
        raise exception 'a payment account needs a valid IBAN' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
      end if;
      v_primary := case when v_account ? 'isPrimary' then (v_account ->> 'isPrimary')::boolean else null end;
      select x."id" into v_id from "better_supabase"."organization_payment_accounts" x
      where x."tenant_id" = v_tenant and x."iban" = v_iban
        and x."bic" is not distinct from coalesce(nullif(upper(btrim(v_account ->> 'bic')), ''), x."bic")
        and x."holder" is not distinct from coalesce(nullif(btrim(v_account ->> 'holder'), ''), x."holder")
        and x."label" is not distinct from coalesce(nullif(btrim(v_account ->> 'label'), ''), x."label")
        and (v_primary is null or x."is_primary" = v_primary);
      if v_id is null then
        if v_primary is true then
          update "better_supabase"."organization_payment_accounts" x set "is_primary" = false where x."tenant_id" = v_tenant and x."iban" <> v_iban;
        end if;
        insert into "better_supabase"."organization_payment_accounts" ("tenant_id", "iban", "bic", "holder", "label", "is_primary")
        values (v_tenant, v_iban, nullif(upper(btrim(v_account ->> 'bic')), ''), nullif(btrim(v_account ->> 'holder'), ''),
          nullif(btrim(v_account ->> 'label'), ''), coalesce(v_primary, false))
        on conflict ("tenant_id", "iban") do update set
          "bic" = coalesce(excluded."bic", "better_supabase"."organization_payment_accounts"."bic"),
          "holder" = coalesce(excluded."holder", "better_supabase"."organization_payment_accounts"."holder"),
          "label" = coalesce(excluded."label", "better_supabase"."organization_payment_accounts"."label"),
          "is_primary" = case when v_primary is true then true else "better_supabase"."organization_payment_accounts"."is_primary" end,
          "updated_at" = now();
      end if;
    end loop;
  end if;
  return jsonb_build_object('subjectId', v_tenant, 'updatedAt', coalesce(v_updated, now()), 'warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."import_organization_profile"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_organization_profile"(uuid, jsonb, text) to service_role;

create or replace function "better_supabase"."organization_profile_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."organization_profiles" x where x."tenant_id"::text = organization_profile_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."organization_profile_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."organization_profile_updated_at"(text) to service_role;

-- better-supabase module: organizations
-- @bsb-block-data organizations
-- @bsb-hash sha256:0d61554664bed8777168e5f25e0b8597db7416b5b7439e346866162aed0f4f0b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('organizations', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== invitations
-- better-supabase module: invitations
-- @bsb-block invitations@2 managed
-- @bsb-hash sha256:5222241440b27249077dd0eab0eafd48a8147c0e9f3ceff3e53f2af58e1d62a9
-- invite_member(tenant, email, role) returns a single-use token whose hash is stored; accept_invitation(token) checks the signed-in user's confirmed email and, again, the inviter's authority. Roles follow the access model; a null tenant invites to a platform role, stored in platform_invitations.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."invitations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "email" text not null,
  "role" text not null,
  "token_hash" text not null unique,
  "expires_at" timestamptz not null,
  "accepted_at" timestamptz
);
alter table "better_supabase"."invitations" alter column "tenant_id" set not null;
alter table "better_supabase"."invitations" alter column "role" drop default;
alter table "better_supabase"."invitations" add column "invited_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."invitations" add column "created_at" timestamptz not null default now();
alter table "better_supabase"."invitations" add column "accepted_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."invitations" add column "declined_at" timestamptz;
alter table "better_supabase"."invitations" add column "revoked_at" timestamptz;
alter table "better_supabase"."invitations" add column "extra_roles" text[] not null default '{}';
alter table "better_supabase"."invitations" add column "team_ids" uuid[] not null default '{}';
create unique index invitations_open_email_idx
  on "better_supabase"."invitations" ("tenant_id", lower("email")) where "accepted_at" is null and "declined_at" is null and "revoked_at" is null;
create index invitations_tenant_created_idx on "better_supabase"."invitations" ("tenant_id", "created_at");
alter table "better_supabase"."invitations" add column "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "better_supabase"."invitations"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
create index invitations_invited_by_idx on "better_supabase"."invitations" ("invited_by");
create index invitations_accepted_by_idx on "better_supabase"."invitations" ("accepted_by");
alter table "better_supabase"."invitations"
  add constraint bsb_invitations_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

alter table "better_supabase"."invitations" enable row level security;
revoke all on "better_supabase"."invitations" from public, anon, authenticated;
grant select on "better_supabase"."invitations" to authenticated;
grant all on "better_supabase"."invitations" to service_role;

-- PL/pgSQL resolves tenant_ids_with when it runs, so this file installs
-- before the access module's.
create or replace function "better_supabase"."invitation_tenant_ids"()
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query select better_supabase.tenant_ids_with('members.invite');
end;
$$;
revoke execute on function "better_supabase"."invitation_tenant_ids"() from public, anon;
grant execute on function "better_supabase"."invitation_tenant_ids"() to authenticated, service_role;
create policy bsb_invitations_read on "better_supabase"."invitations"
  for select to authenticated
  using ("tenant_id" in (select "better_supabase"."invitation_tenant_ids"()));

-- The keys an invitation_preview_extra(invitation uuid) hook returns for an
-- invitation, such as a role's display name; {} without the hook. The
-- module's functions merge them into every invitation they return.
create or replace function "better_supabase"."invitation_extra"(invitation uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  hook regprocedure := to_regprocedure('"public"."invitation_preview_extra"(uuid)');
  extra jsonb;
begin
  if hook is null or invitation is null then
    return '{}'::jsonb;
  end if;
  -- Not a literal name, so plpgsql_check passes without the hook.
  execute format('select %s($1)', hook::oid::regproc) into extra using invitation;
  return coalesce(extra, '{}'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."invitation_extra"(uuid) from public, anon, authenticated;

-- Invites email to tenant (null: a platform invitation) with role, a catalog
-- role id or key under blocks.permissions.model 'catalog'. Returns the invitation
-- and its token; only the token's hash is stored. An open invitation for
-- the same email is replaced.

create or replace function "better_supabase"."invite_member"(
  tenant uuid,
  invitee_email text,
  invitee_role text,
  valid_for interval default '7 days',
  prefill jsonb default '{}', on_accept jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  created "better_supabase"."invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  if tenant is null then
    raise exception 'Platform invitations need platform roles: blocks.permissions.model ''catalog'' with platform assignments, or blocks.invitations.options.platformRoles under ''provider''' using errcode = '0A000', hint = 'INVITATION_SCOPE_UNSUPPORTED';
  end if;
  invitee_role := coalesce(invitee_role, 'admin');
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or not exists (select 1 from "better_supabase"."organizations" o where o."id" = tenant) then
    raise exception 'The organization is not active' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invitee_role = any (array['owner', 'admin', 'member', 'viewer']::text[])) then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and not better_supabase.can_assign(tenant, (invitee_role)::text) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
  end if;
  if exists (
    select 1 from "better_supabase"."memberships" m join auth.users u on u.id = m."user_id"
    where m."organization_id" = tenant and lower(u.email) = lower(btrim(invitee_email))
  ) then
    raise exception '% is already a member', invitee_email using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invitation_create"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tenant, invitee_email, invitee_role;
    end if;
  end;
  delete from "better_supabase"."invitations" i
  where i."tenant_id" = tenant
    and lower(i."email") = lower(btrim(invitee_email))
    and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  insert into "better_supabase"."invitations" ("tenant_id", "email", "role", "token_hash", "invited_by", "expires_at")
  values (tenant, lower(btrim(invitee_email)), invitee_role, encode(extensions.digest(token, 'sha256'), 'hex'), auth.uid(), now() + valid_for)
  returning * into created;
  if on_accept is not null then
    declare
      accept_roles text[];
      accept_teams uuid[];
    begin
      if jsonb_typeof(on_accept) <> 'object' or exists (
        select 1 from jsonb_object_keys(on_accept) k where k not in ('roles', 'teams')
      ) then
        raise exception 'on_accept takes roles and teams' using errcode = '22023', hint = 'INVITATION_ON_ACCEPT_INVALID';
      end if;
      accept_roles := array(select jsonb_array_elements_text(coalesce(on_accept -> 'roles', '[]')));
      if exists (select 1 from unnest(accept_roles) r(role) where not (r.role = any (array['owner', 'admin', 'member', 'viewer']::text[]))) then
        raise exception 'Unknown role in on_accept.roles' using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
      end if;
      if not service and exists (select 1 from unnest(accept_roles) r(role) where not better_supabase.can_assign(tenant, r.role)) then
        raise exception 'A role in on_accept.roles is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
      end if;
      update "better_supabase"."invitations" set "extra_roles" = accept_roles where "id" = created."id";
      accept_teams := array(select (jsonb_array_elements_text(coalesce(on_accept -> 'teams', '[]')))::uuid);
      if exists (
        select 1 from unnest(accept_teams) x(id)
        where not exists (select 1 from "better_supabase"."teams" tm where tm."id" = x.id and tm."tenant_id" = tenant)
      ) then
        raise exception 'A team in on_accept.teams is not in this organization' using errcode = '23514', hint = 'INVITATION_TEAM_UNKNOWN';
      end if;
      update "better_supabase"."invitations" set "team_ids" = accept_teams where "id" = created."id";
    end;
  end if;
  null;
  return (jsonb_build_object(
    'id', created."id",
    'tenant', created."tenant_id",
    'email', created."email",
    'role', created."role",
    'expires_at', created."expires_at",
    'created_at', created."created_at",
    'invited_by', created."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "better_supabase"."organizations" o where o."id" = created."tenant_id"),
    'prefill', '{}'::jsonb,
    'token', token
  ) || "better_supabase"."invitation_extra"(created."id"));
end;
$$;

-- The 0.4 signature: returns the token only.

create or replace function "better_supabase"."create_invitation"(
  organization uuid,
  invitee_email text,
  invitee_role text default 'admin',
  valid_for interval default '7 days'
)
returns text
language sql
security invoker
set search_path = ''
as $$
  select "better_supabase"."invite_member"($1, $2, $3, $4) ->> 'token'
$$;

-- A new token and expiry for an open invitation; the old token stops working.
create or replace function "better_supabase"."resend_invitation"(invitation_id uuid, valid_for interval default '7 days')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  updated "better_supabase"."invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  update "better_supabase"."invitations" i
  set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "expires_at" = now() + valid_for
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."tenant_id", 'members.invite'), false))
  returning * into updated;
  if updated."id" is null then
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  null;
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."tenant_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "better_supabase"."organizations" o where o."id" = updated."tenant_id"),
    'prefill', '{}'::jsonb,
    'token', token
  ) || "better_supabase"."invitation_extra"(updated."id"));
end;
$$;

-- A new email, role or prefill for an open invitation that has not expired;
-- null keeps the current value. The caller needs what invite_member needs, and may assign
-- both the current and the new role. The token and expiry stay, and another
-- open invitation for the new email is replaced. Returns the invitation
-- without its token.
create or replace function "better_supabase"."update_invitation"(
  invitation_id uuid,
  invitee_email text default null,
  invitee_role text default null,
  prefill jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  current_invite "better_supabase"."invitations";
  updated "better_supabase"."invitations";
  tenant uuid;
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
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if current_invite."expires_at" < now() then
    raise exception 'The invitation has expired; resend it to renew it' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  tenant := current_invite."tenant_id";
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or not exists (select 1 from "better_supabase"."organizations" o where o."id" = tenant) then
    raise exception 'The organization is not active' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invitee_role is not null and not (invitee_role = any (array['owner', 'admin', 'member', 'viewer']::text[])) then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and (
    not better_supabase.can_assign(tenant, current_invite."role"::text)
    or (invitee_role is not null and not better_supabase.can_assign(tenant, (invitee_role)::text))
  ) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
  end if;
  if invitee_email is not null and exists (
    select 1 from "better_supabase"."memberships" m join auth.users u on u.id = m."user_id"
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
      updated."role" := invitee_role;
    end if;
    update "better_supabase"."invitations" i
    set "email" = updated."email",
      "role" = updated."role"
    where i."id" = invitation_id
    returning * into updated;
  null;
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."tenant_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "better_supabase"."organizations" o where o."id" = updated."tenant_id"),
    'prefill', '{}'::jsonb,
    'token', null
  ) || "better_supabase"."invitation_extra"(updated."id")) - 'token';
end;
$$;

-- Revokes an open invitation (deletes it when revokedAt is mapped to null).
create or replace function "better_supabase"."revoke_invitation"(invitation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  tenant text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."invitations" i set "revoked_at" = now() where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."tenant_id", 'members.invite'), false)) and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."tenant_id"::text into tenant;
  if found then
    null;
    return true;
  end if;
  return false;
end;
$$;

-- The invitee declines with the token, signed in or not.
create or replace function "better_supabase"."decline_invitation"(token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  declined_id uuid;
  tenant text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."invitations" i set "declined_at" = now() where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex') and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id", i."tenant_id"::text into declined_id, tenant;
  if declined_id is not null then
    null;
    return true;
  end if;
  return false;
end;
$$;

create or replace function "better_supabase"."decline_invitation_by_id"(invitation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  declined_id uuid;
  tenant text;
  invitee_email text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select lower(u.email) into invitee_email
  from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;
  if invitee_email is null then
    return false;
  end if;
  update "better_supabase"."invitations" i set "declined_at" = now() where i."id" = invitation_id and lower(i."email") = invitee_email and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id", i."tenant_id"::text into declined_id, tenant;
  if declined_id is not null then
    null;
    return true;
  end if;
  return false;
end;
$$;

-- What an invitation link shows before sign-in: status (pending, accepted,
-- declined, revoked or expired), email, role, organization (id plus
-- blocks.invitations.options.previewColumns) and prefill. Null for an unknown token.
-- An invitation_preview_extra(invitation uuid) returns jsonb hook adds its
-- keys, such as a role's display name or branding from another table.
create or replace function "better_supabase"."invitation_preview"(token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  preview jsonb;
  invitation uuid;
begin
  select jsonb_build_object(
    'status', case
    when i."accepted_at" is not null then 'accepted'
    when i."declined_at" is not null then 'declined'
    when i."revoked_at" is not null then 'revoked'
    when i."expires_at" < now() then 'expired'
    else 'pending'
  end,
    'email', i."email",
    'role', i."role",
    'tenant', i."tenant_id",
    'expires_at', i."expires_at",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "better_supabase"."organizations" o where o."id" = i."tenant_id"),
    'prefill', '{}'::jsonb
  ), i."id"
  into preview, invitation
  from "better_supabase"."invitations" i
  where i."token_hash" = encode(extensions.digest(invitation_preview.token, 'sha256'), 'hex');
  if preview is not null then
    preview := preview || "better_supabase"."invitation_extra"(invitation);
  end if;
  return preview;
end;
$$;

create or replace function "better_supabase"."accepting_invitation"()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(current_setting('better_supabase.accepting_invitation', true), '')::uuid
$$;

-- Accepts with the token for the signed-in user, whose confirmed email must
-- match, and returns the tenant (null for a platform invitation).
create or replace function "better_supabase"."accept_invitation"(token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
  invite "better_supabase"."invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "better_supabase"."invitations" i
  where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex')
  for update;
  if invite."id" is null then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invite."accepted_at" is null and invite."declined_at" is null and invite."revoked_at" is null) then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invite."expires_at" < now() then
    raise exception 'The invitation has expired; ask for a new one' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  if lower(invite."email") <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(invite."email")
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  if invite."invited_by" = me then
    raise exception 'You cannot accept your own invitation' using errcode = '42501', hint = 'INVITATION_SELF';
  end if;
  if better_supabase.tenant_disabled(invite."tenant_id") or not exists (select 1 from "better_supabase"."organizations" o where o."id" = invite."tenant_id") then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = invite."tenant_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."tenant_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."tenant_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  perform set_config('better_supabase.accepting_invitation', invite."id"::text, true);
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (invite."tenant_id", me, invite."role");
  insert into "better_supabase"."membership_roles" ("organization_id", "user_id", "role")
  select invite."tenant_id", me, r.role from unnest(invite."extra_roles") r(role)
  on conflict do nothing;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "tenant_id")
  select x.id, me, invite."tenant_id" from unnest(invite."team_ids") x(id)
  where exists (
    select 1 from "better_supabase"."teams" tt
    where tt."id" = x.id and tt."tenant_id" = invite."tenant_id"
  )
  on conflict do nothing;
  perform set_config('better_supabase.accepting_invitation', '', true);
  update "better_supabase"."invitations"
  set "accepted_at" = now(), "accepted_by" = me
  where "id" = invite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using invite."id", me;
    end if;
  end;
  null;
  null;
  return invite."tenant_id";
end;
$$;

create or replace function "better_supabase"."accept_invitation_by_id"(invitation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
  invite "better_supabase"."invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "better_supabase"."invitations" i
  where i."id" = invitation_id
  for update;
  if invite."id" is null then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invite."accepted_at" is null and invite."declined_at" is null and invite."revoked_at" is null) then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invite."expires_at" < now() then
    raise exception 'The invitation has expired; ask for a new one' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  if lower(invite."email") <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(invite."email")
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  if invite."invited_by" = me then
    raise exception 'You cannot accept your own invitation' using errcode = '42501', hint = 'INVITATION_SELF';
  end if;
  if better_supabase.tenant_disabled(invite."tenant_id") or not exists (select 1 from "better_supabase"."organizations" o where o."id" = invite."tenant_id") then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = invite."tenant_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."tenant_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."tenant_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  perform set_config('better_supabase.accepting_invitation', invite."id"::text, true);
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (invite."tenant_id", me, invite."role");
  insert into "better_supabase"."membership_roles" ("organization_id", "user_id", "role")
  select invite."tenant_id", me, r.role from unnest(invite."extra_roles") r(role)
  on conflict do nothing;
  insert into "better_supabase"."team_members" ("team_id", "user_id", "tenant_id")
  select x.id, me, invite."tenant_id" from unnest(invite."team_ids") x(id)
  where exists (
    select 1 from "better_supabase"."teams" tt
    where tt."id" = x.id and tt."tenant_id" = invite."tenant_id"
  )
  on conflict do nothing;
  perform set_config('better_supabase.accepting_invitation', '', true);
  update "better_supabase"."invitations"
  set "accepted_at" = now(), "accepted_by" = me
  where "id" = invite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using invite."id", me;
    end if;
  end;
  null;
  null;
  return invite."tenant_id";
end;
$$;

-- The caller's open invitations, for an in-app inbox: the invitation without
-- its token, its organization (id plus previewColumns) and the keys an
-- invitation_preview_extra(invitation uuid) hook adds.
create or replace function "better_supabase"."my_invitations"()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  invitee_email text;
  result jsonb := '[]'::jsonb;
begin
  select lower(u.email) into invitee_email
  from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;
  if invitee_email is null then
    return result;
  end if;
  select coalesce(jsonb_agg(x.invitation order by x.expires_at), '[]'::jsonb)
  into result
  from (
    select (jsonb_build_object(
    'id', i."id",
    'tenant', i."tenant_id",
    'email', i."email",
    'role', i."role",
    'expires_at', i."expires_at",
    'created_at', i."created_at",
    'invited_by', i."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "better_supabase"."organizations" o where o."id" = i."tenant_id"),
    'prefill', '{}'::jsonb,
    'token', null
  ) || "better_supabase"."invitation_extra"(i."id")) - 'token' as invitation, i."id" as id, i."expires_at" as expires_at
    from "better_supabase"."invitations" i
    where lower(i."email") = invitee_email
      and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  ) x;
  return result;
end;
$$;

revoke execute on function "better_supabase"."invite_member"(uuid, text, text, interval, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."invite_member"(uuid, text, text, interval, jsonb, jsonb) to authenticated, service_role;
revoke execute on function "better_supabase"."create_invitation"(uuid, text, text, interval) from public, anon;
grant execute on function "better_supabase"."create_invitation"(uuid, text, text, interval) to authenticated, service_role;
revoke execute on function "better_supabase"."resend_invitation"(uuid, interval) from public, anon;
grant execute on function "better_supabase"."resend_invitation"(uuid, interval) to authenticated, service_role;
revoke execute on function "better_supabase"."update_invitation"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."update_invitation"(uuid, text, text, jsonb) to authenticated, service_role;
revoke execute on function "better_supabase"."revoke_invitation"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_invitation"(uuid) to authenticated, service_role;
revoke execute on function "better_supabase"."decline_invitation"(text) from public;
grant execute on function "better_supabase"."decline_invitation"(text) to anon, authenticated, service_role;
revoke execute on function "better_supabase"."invitation_preview"(text) from public;
grant execute on function "better_supabase"."invitation_preview"(text) to anon, authenticated, service_role;
revoke execute on function "better_supabase"."accept_invitation"(text) from public, anon;
grant execute on function "better_supabase"."accept_invitation"(text) to authenticated;
revoke execute on function "better_supabase"."accept_invitation_by_id"(uuid) from public, anon;
grant execute on function "better_supabase"."accept_invitation_by_id"(uuid) to authenticated;
revoke execute on function "better_supabase"."decline_invitation_by_id"(uuid) from public, anon;
grant execute on function "better_supabase"."decline_invitation_by_id"(uuid) to authenticated;
revoke execute on function "better_supabase"."my_invitations"() from public, anon;
grant execute on function "better_supabase"."my_invitations"() to authenticated;
revoke execute on function "better_supabase"."accepting_invitation"() from public, anon;
grant execute on function "better_supabase"."accepting_invitation"() to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."invitations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select "better_supabase"."invitation_tenant_ids"()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."invitations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."invitations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."invitations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- better-supabase module: invitations
-- @bsb-block-data invitations
-- @bsb-hash sha256:af5820c76152303a41d469d66eed44a659f4e2f38ee513d3d7f862a9a7932c8c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('invitations', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
