-- better-supabase module: invitations
-- @bsb-block invitations@2 managed
-- @bsb-hash sha256:d1668cbb7d0b24091dafadda48bbc7069ced05d030d97221997ceac044f4aa2f
-- invite_member(tenant, email, role) returns a single-use token whose hash is stored; accept_invitation(token) checks the signed-in user's confirmed email and, again, the inviter's authority. Roles follow the access model; a null tenant invites to a platform role, stored in platform_invitations.
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
    drop policy if exists bsb_tenant_scope on "centrakit"."organization_invitations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- centrakit.organization_invitations is the app's table, and it has every column this block needs.
alter table "centrakit"."organization_invitations" add column if not exists "invited_by" uuid references auth.users (id) on delete set null;
alter table "centrakit"."organization_invitations" add column if not exists "created_at" timestamptz not null default now();
alter table "centrakit"."organization_invitations" add column if not exists "declined_at" timestamptz;
alter table "centrakit"."organization_invitations" add column if not exists "prefill" jsonb not null default '{}';

drop index if exists "centrakit".invitations_open_idx;
create unique index if not exists invitations_open_email_idx
  on "centrakit"."organization_invitations" ("organization_id", lower("email")) where "accepted_at" is null and "declined_at" is null;
create index if not exists invitations_tenant_created_idx on "centrakit"."organization_invitations" ("organization_id", "created_at");
alter table "centrakit"."organization_invitations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "centrakit"."organization_invitations";
create trigger bsb_updated_at before update on "centrakit"."organization_invitations"
  for each row execute function better_supabase.set_updated_at('updated_at');
create index if not exists invitations_invited_by_idx on "centrakit"."organization_invitations" ("invited_by");


alter table "centrakit"."organization_invitations" enable row level security;
grant select on "centrakit"."organization_invitations" to authenticated;
grant all on "centrakit"."organization_invitations" to service_role;

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
drop policy if exists bsb_invitations_read on "centrakit"."organization_invitations";
create policy bsb_invitations_read on "centrakit"."organization_invitations" for select to authenticated
  using ("organization_id" in (select "better_supabase"."invitation_tenant_ids"()));

-- Invitations to a platform role (the catalog model's platform assignments).
-- centrakit.organization_invitations is the app's table, and it has every column this block needs.
alter table "centrakit"."organization_invitations" add column if not exists "invited_by" uuid references auth.users (id) on delete set null;
alter table "centrakit"."organization_invitations" add column if not exists "created_at" timestamptz not null default now();
alter table "centrakit"."organization_invitations" add column if not exists "declined_at" timestamptz;

create unique index if not exists platform_invitations_open_email_idx
  on "centrakit"."organization_invitations" (lower("email")) where "accepted_at" is null and "declined_at" is null;
alter table "centrakit"."organization_invitations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "centrakit"."organization_invitations";
create trigger bsb_updated_at before update on "centrakit"."organization_invitations"
  for each row execute function better_supabase.set_updated_at('updated_at');
create index if not exists platform_invitations_invited_by_idx on "centrakit"."organization_invitations" ("invited_by");

alter table "centrakit"."organization_invitations" enable row level security;
grant select on "centrakit"."organization_invitations" to authenticated;
grant all on "centrakit"."organization_invitations" to service_role;
create or replace function "better_supabase"."platform_invitations_readable"()
returns boolean
language plpgsql
stable
set search_path = ''
as $$
begin
  return (select coalesce(better_supabase.is_platform('platform.invite'), false));
end;
$$;
revoke execute on function "better_supabase"."platform_invitations_readable"() from public, anon;
grant execute on function "better_supabase"."platform_invitations_readable"() to authenticated, service_role;
-- Tenant and platform invitations share "centrakit"."organization_invitations", so one policy reads both.
drop policy if exists bsb_platform_invitations_read on "centrakit"."organization_invitations";
drop policy if exists bsb_invitations_read on "centrakit"."organization_invitations";
create policy bsb_invitations_read on "centrakit"."organization_invitations" for select to authenticated
  using ("organization_id" in (select "better_supabase"."invitation_tenant_ids"()) or (select "better_supabase"."platform_invitations_readable"()));

-- blocks.invitations.options.platformRoles.through.where names the
-- platform roles. Every write to "centrakit"."user_roles" stores one of them,
-- whoever writes it: a client policy, the service role or an admin connection.
create or replace function "better_supabase"."platform_role_scope"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."role_id" is not null and not exists (
    select 1 from "centrakit"."roles" r
    where r."id"::text = new."role_id"::text and (r.scope = 'system')
  ) then
    raise exception 'Role % is not a platform role', new."role_id"
      using errcode = '23514', hint = 'PLATFORM_ROLE_SCOPE';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."platform_role_scope"() from public, anon, authenticated;
drop trigger if exists "bsb_role_scope" on "centrakit"."user_roles";
create trigger "bsb_role_scope" before insert or update of "role_id" on "centrakit"."user_roles"
  for each row execute function "better_supabase"."platform_role_scope"();

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
drop function if exists "better_supabase"."invite_member"(uuid, text, text, interval, jsonb, jsonb);
create or replace function "better_supabase"."invite_member"(
  tenant uuid,
  invitee_email text,
  invitee_role text,
  valid_for interval default '7 days',
  prefill jsonb default '{}'
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
  created "centrakit"."organization_invitations";
  platform_created "centrakit"."organization_invitations";
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  if tenant is null then
    if not service and not (select coalesce(better_supabase.is_platform('platform.invite'), false)) then
      raise exception 'Not allowed to invite platform users' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
    end if;
    if (select r."id" from "centrakit"."roles" r where (r."id"::text = (invitee_role)::text or r."key"::text = (invitee_role)::text) and (r.scope = 'system') order by (r."id"::text = (invitee_role)::text) desc limit 1) is null then
      raise exception 'Unknown platform role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
    end if;
    -- No platform role ceiling: holding the invite permission is enough.
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_invitation_create"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tenant, invitee_email, invitee_role;
    end if;
  end;
    delete from "centrakit"."organization_invitations" i
    where lower(i."email") = lower(btrim(invitee_email)) and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is null;
    insert into "centrakit"."organization_invitations" ("email", "role_id", "token", "invited_by", "expires_at", "prefill")
    values (lower(btrim(invitee_email)), (select r."id" from "centrakit"."roles" r where (r."id"::text = (invitee_role)::text or r."key"::text = (invitee_role)::text) and (r.scope = 'system') order by (r."id"::text = (invitee_role)::text) desc limit 1), token, auth.uid(), now() + valid_for, coalesce(prefill, '{}'))
    returning * into platform_created;
    perform "better_supabase".emit_event('invitation.created', jsonb_build_object('invitationId', platform_created."id", 'organizationId', null, 'email', platform_created."email", 'role', platform_created."role_id"), 'invitations/' || platform_created."id"::text, null, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.created',
    category => 'membership',
    target_type => 'invitation',
    record_id => platform_created."id"::text,
    metadata => jsonb_build_object('invitationId', platform_created."id", 'organizationId', null, 'email', platform_created."email", 'role', platform_created."role_id")
  );
    return (jsonb_build_object(
    'id', platform_created."id",
    'tenant', null,
    'email', platform_created."email",
    'role', platform_created."role_id",
    'expires_at', platform_created."expires_at",
    'created_at', platform_created."created_at",
    'invited_by', platform_created."invited_by",
    'organization', null,
    'prefill', platform_created."prefill",
    'inviter', (select jsonb_build_object('id', pr."user_id", 'username', pr."username", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_path")
      from "centrakit"."profiles" pr where pr."user_id" = platform_created."invited_by"),
    'token', token
  ) || "better_supabase"."invitation_extra"(platform_created."id"));
  end if;
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or not exists (select 1 from "centrakit"."organizations" o where o."id" = tenant) then
    raise exception 'The organization is not active' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if (select r."id" from "centrakit"."roles" r where (r."id"::text = (invitee_role)::text or r."key"::text = (invitee_role)::text) and (r.scope = 'organization') order by (r."id"::text = (invitee_role)::text) desc limit 1) is null then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and not better_supabase.can_assign(tenant, (select r."key"::text from "centrakit"."roles" r where r."id"::text = (((select r."id" from "centrakit"."roles" r where (r."id"::text = (invitee_role)::text or r."key"::text = (invitee_role)::text) and (r.scope = 'organization') order by (r."id"::text = (invitee_role)::text) desc limit 1)))::text)) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
  end if;
  if exists (
    select 1 from "centrakit"."organization_users" m join auth.users u on u.id = m."user_id"
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
  delete from "centrakit"."organization_invitations" i
  where i."organization_id" = tenant
    and lower(i."email") = lower(btrim(invitee_email))
    and i."accepted_at" is null and i."declined_at" is null;
  insert into "centrakit"."organization_invitations" ("organization_id", "email", "role_id", "token", "invited_by", "expires_at", "prefill")
  values (tenant, lower(btrim(invitee_email)), (select r."id" from "centrakit"."roles" r where (r."id"::text = (invitee_role)::text or r."key"::text = (invitee_role)::text) and (r.scope = 'organization') order by (r."id"::text = (invitee_role)::text) desc limit 1), token, auth.uid(), now() + valid_for, coalesce(prefill, '{}'))
  returning * into created;
  perform "better_supabase".emit_event('invitation.created', jsonb_build_object('invitationId', created."id", 'organizationId', tenant::text, 'email', created."email", 'role', created."role_id"), 'invitations/' || created."id"::text, (tenant)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.created',
    category => 'membership',
    target_type => 'invitation',
    record_id => created."id"::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', created."id", 'organizationId', tenant::text, 'email', created."email", 'role', created."role_id")
  );
  return (jsonb_build_object(
    'id', created."id",
    'tenant', created."organization_id",
    'email', created."email",
    'role', created."role_id",
    'expires_at', created."expires_at",
    'created_at', created."created_at",
    'invited_by', created."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "centrakit"."organizations" o where o."id" = created."organization_id"),
    'prefill', created."prefill",
    'inviter', (select jsonb_build_object('id', pr."user_id", 'username', pr."username", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_path")
      from "centrakit"."profiles" pr where pr."user_id" = created."invited_by"),
    'token', token
  ) || "better_supabase"."invitation_extra"(created."id"));
end;
$$;

-- The 0.4 signature: returns the token only.
drop function if exists "better_supabase"."create_invitation"(uuid, text, text, interval);
create or replace function "better_supabase"."create_invitation"(
  organization uuid,
  invitee_email text,
  invitee_role text default 'member',
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
  updated "centrakit"."organization_invitations";
  platform_updated "centrakit"."organization_invitations";
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  update "centrakit"."organization_invitations" i
  set "token" = token,
    "expires_at" = now() + valid_for
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is not null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false))
  returning * into updated;
  if updated."id" is null then
    update "centrakit"."organization_invitations" i
    set "token" = token,
      "expires_at" = now() + valid_for
    where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is null
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('platform.invite'), false)))
    returning * into platform_updated;
    if platform_updated."id" is not null then
      perform "better_supabase".emit_event('invitation.resent', jsonb_build_object('invitationId', platform_updated."id", 'organizationId', null, 'email', platform_updated."email"), 'invitations/' || platform_updated."id"::text, null, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.resent',
    category => 'membership',
    target_type => 'invitation',
    record_id => platform_updated."id"::text,
    metadata => jsonb_build_object('invitationId', platform_updated."id", 'organizationId', null, 'email', platform_updated."email")
  );
      return (jsonb_build_object(
    'id', platform_updated."id",
    'tenant', null,
    'email', platform_updated."email",
    'role', platform_updated."role_id",
    'expires_at', platform_updated."expires_at",
    'created_at', platform_updated."created_at",
    'invited_by', platform_updated."invited_by",
    'organization', null,
    'prefill', platform_updated."prefill",
    'inviter', (select jsonb_build_object('id', pr."user_id", 'username', pr."username", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_path")
      from "centrakit"."profiles" pr where pr."user_id" = platform_updated."invited_by"),
    'token', token
  ) || "better_supabase"."invitation_extra"(platform_updated."id"));
    end if;
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  perform "better_supabase".emit_event('invitation.resent', jsonb_build_object('invitationId', updated."id", 'organizationId', updated."organization_id"::text, 'email', updated."email"), 'invitations/' || updated."id"::text, (updated."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.resent',
    category => 'membership',
    target_type => 'invitation',
    record_id => updated."id"::text,
    tenant => (updated."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', updated."id", 'organizationId', updated."organization_id"::text, 'email', updated."email")
  );
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role_id",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "centrakit"."organizations" o where o."id" = updated."organization_id"),
    'prefill', updated."prefill",
    'inviter', (select jsonb_build_object('id', pr."user_id", 'username', pr."username", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_path")
      from "centrakit"."profiles" pr where pr."user_id" = updated."invited_by"),
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
  current_invite "centrakit"."organization_invitations";
  updated "centrakit"."organization_invitations";
  tenant uuid;
  platform_current "centrakit"."organization_invitations";
  platform_updated "centrakit"."organization_invitations";
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if invitee_email is not null and btrim(invitee_email) = '' then
    raise exception 'The email address is empty' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  select * into current_invite from "centrakit"."organization_invitations" i
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is not null
  for update;
  if current_invite."id" is null then
    select * into platform_current from "centrakit"."organization_invitations" i
    where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is null
    for update;
    if platform_current."id" is not null then
      if platform_current."expires_at" < now() then
        raise exception 'The invitation has expired; resend it to renew it' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
      end if;
      if not service and not (select coalesce(better_supabase.is_platform('platform.invite'), false)) then
        raise exception 'Not allowed to invite platform users' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
      end if;
      if invitee_role is not null and (select r."id" from "centrakit"."roles" r where (r."id"::text = (invitee_role)::text or r."key"::text = (invitee_role)::text) and (r.scope = 'system') order by (r."id"::text = (invitee_role)::text) desc limit 1) is null then
        raise exception 'Unknown platform role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
      end if;
      -- No platform role ceiling: holding the invite permission is enough.
      if invitee_email is not null then
        delete from "centrakit"."organization_invitations" i
        where lower(i."email") = lower(btrim(invitee_email))
          and i."id" <> invitation_id and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is null;
      end if;
      platform_updated := platform_current;
    if invitee_email is not null then
      platform_updated."email" := lower(btrim(invitee_email));
    end if;
    if invitee_role is not null then
      platform_updated."role_id" := (select r."id" from "centrakit"."roles" r where (r."id"::text = (invitee_role)::text or r."key"::text = (invitee_role)::text) and (r.scope = 'system') order by (r."id"::text = (invitee_role)::text) desc limit 1);
    end if;
    if prefill is not null then
      platform_updated."prefill" := prefill;
    end if;
    update "centrakit"."organization_invitations" i
    set "email" = platform_updated."email",
      "role_id" = platform_updated."role_id",
      "prefill" = platform_updated."prefill"
    where i."id" = invitation_id
    returning * into platform_updated;
      perform "better_supabase".emit_event('invitation.updated', jsonb_build_object('invitationId', platform_updated."id", 'organizationId', null, 'email', platform_updated."email", 'role', platform_updated."role_id"), 'invitations/' || platform_updated."id"::text, null, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.updated',
    category => 'membership',
    target_type => 'invitation',
    record_id => platform_updated."id"::text,
    metadata => jsonb_build_object('invitationId', platform_updated."id", 'organizationId', null, 'email', platform_updated."email", 'role', platform_updated."role_id")
  );
      return (jsonb_build_object(
    'id', platform_updated."id",
    'tenant', null,
    'email', platform_updated."email",
    'role', platform_updated."role_id",
    'expires_at', platform_updated."expires_at",
    'created_at', platform_updated."created_at",
    'invited_by', platform_updated."invited_by",
    'organization', null,
    'prefill', platform_updated."prefill",
    'inviter', (select jsonb_build_object('id', pr."user_id", 'username', pr."username", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_path")
      from "centrakit"."profiles" pr where pr."user_id" = platform_updated."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(platform_updated."id")) - 'token';
    end if;
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if current_invite."expires_at" < now() then
    raise exception 'The invitation has expired; resend it to renew it' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  tenant := current_invite."organization_id";
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or not exists (select 1 from "centrakit"."organizations" o where o."id" = tenant) then
    raise exception 'The organization is not active' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if invitee_role is not null and (select r."id" from "centrakit"."roles" r where (r."id"::text = (invitee_role)::text or r."key"::text = (invitee_role)::text) and (r.scope = 'organization') order by (r."id"::text = (invitee_role)::text) desc limit 1) is null then
    raise exception 'Unknown role %', invitee_role using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  if not service and (
    not better_supabase.can_assign(tenant, (select r."key"::text from "centrakit"."roles" r where r."id"::text = (current_invite."role_id")::text))
    or (invitee_role is not null and not better_supabase.can_assign(tenant, (select r."key"::text from "centrakit"."roles" r where r."id"::text = (((select r."id" from "centrakit"."roles" r where (r."id"::text = (invitee_role)::text or r."key"::text = (invitee_role)::text) and (r.scope = 'organization') order by (r."id"::text = (invitee_role)::text) desc limit 1)))::text)))
  ) then
    raise exception 'That role is above your own' using errcode = '42501', hint = 'INVITATION_ROLE_FORBIDDEN';
  end if;
  if invitee_email is not null and exists (
    select 1 from "centrakit"."organization_users" m join auth.users u on u.id = m."user_id"
    where m."organization_id" = tenant and lower(u.email) = lower(btrim(invitee_email))
  ) then
    raise exception '% is already a member', invitee_email using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
  if invitee_email is not null then
    delete from "centrakit"."organization_invitations" i
    where i."organization_id" = tenant
      and lower(i."email") = lower(btrim(invitee_email))
      and i."id" <> invitation_id
      and i."accepted_at" is null and i."declined_at" is null;
  end if;
  updated := current_invite;
    if invitee_email is not null then
      updated."email" := lower(btrim(invitee_email));
    end if;
    if invitee_role is not null then
      updated."role_id" := (select r."id" from "centrakit"."roles" r where (r."id"::text = (invitee_role)::text or r."key"::text = (invitee_role)::text) and (r.scope = 'organization') order by (r."id"::text = (invitee_role)::text) desc limit 1);
    end if;
    if prefill is not null then
      updated."prefill" := prefill;
    end if;
    update "centrakit"."organization_invitations" i
    set "email" = updated."email",
      "role_id" = updated."role_id",
      "prefill" = updated."prefill"
    where i."id" = invitation_id
    returning * into updated;
  perform "better_supabase".emit_event('invitation.updated', jsonb_build_object('invitationId', updated."id", 'organizationId', tenant::text, 'email', updated."email", 'role', updated."role_id"), 'invitations/' || updated."id"::text, (tenant)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.updated',
    category => 'membership',
    target_type => 'invitation',
    record_id => updated."id"::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', updated."id", 'organizationId', tenant::text, 'email', updated."email", 'role', updated."role_id")
  );
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role_id",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "centrakit"."organizations" o where o."id" = updated."organization_id"),
    'prefill', updated."prefill",
    'inviter', (select jsonb_build_object('id', pr."user_id", 'username', pr."username", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_path")
      from "centrakit"."profiles" pr where pr."user_id" = updated."invited_by"),
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "centrakit"."organization_invitations" i where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false)) and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is not null
  returning i."organization_id"::text into tenant;
  if found then
    perform "better_supabase".emit_event('invitation.revoked', jsonb_build_object('invitationId', invitation_id, 'organizationId', tenant), 'invitations/' || invitation_id::text, (tenant)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.revoked',
    category => 'membership',
    target_type => 'invitation',
    record_id => invitation_id::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', invitation_id, 'organizationId', tenant)
  );
    return true;
  end if;
  delete from "centrakit"."organization_invitations" i where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (select coalesce(better_supabase.is_platform('platform.invite'), false))) and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is null;
  if found then
    perform "better_supabase".emit_event('invitation.revoked', jsonb_build_object('invitationId', invitation_id, 'organizationId', null), 'invitations/' || invitation_id::text, null, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.revoked',
    category => 'membership',
    target_type => 'invitation',
    record_id => invitation_id::text,
    metadata => jsonb_build_object('invitationId', invitation_id, 'organizationId', null)
  );
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "centrakit"."organization_invitations" i set "declined_at" = now() where i."token" = token and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is not null
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
    perform "better_supabase".emit_event('invitation.declined', jsonb_build_object('invitationId', declined_id, 'organizationId', tenant), 'invitations/' || declined_id::text, (tenant)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.declined',
    category => 'membership',
    target_type => 'invitation',
    record_id => declined_id::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', declined_id, 'organizationId', tenant)
  );
    return true;
  end if;
  update "centrakit"."organization_invitations" i set "declined_at" = now() where i."token" = token and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is null
  returning i."id" into declined_id;
  if declined_id is not null then
    perform "better_supabase".emit_event('invitation.declined', jsonb_build_object('invitationId', declined_id, 'organizationId', null), 'invitations/' || declined_id::text, null, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.declined',
    category => 'membership',
    target_type => 'invitation',
    record_id => declined_id::text,
    metadata => jsonb_build_object('invitationId', declined_id, 'organizationId', null)
  );
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
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select lower(u.email) into invitee_email
  from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;
  if invitee_email is null then
    return false;
  end if;
  update "centrakit"."organization_invitations" i set "declined_at" = now() where i."id" = invitation_id and lower(i."email") = invitee_email and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is not null
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
    perform "better_supabase".emit_event('invitation.declined', jsonb_build_object('invitationId', declined_id, 'organizationId', tenant), 'invitations/' || declined_id::text, (tenant)::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.declined',
    category => 'membership',
    target_type => 'invitation',
    record_id => declined_id::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', declined_id, 'organizationId', tenant)
  );
    return true;
  end if;
  update "centrakit"."organization_invitations" i set "declined_at" = now() where i."id" = invitation_id and lower(i."email") = invitee_email and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is null
  returning i."id" into declined_id;
  if declined_id is not null then
    perform "better_supabase".emit_event('invitation.declined', jsonb_build_object('invitationId', declined_id, 'organizationId', null), 'invitations/' || declined_id::text, null, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.declined',
    category => 'membership',
    target_type => 'invitation',
    record_id => declined_id::text,
    metadata => jsonb_build_object('invitationId', declined_id, 'organizationId', null)
  );
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
    when i."expires_at" < now() then 'expired'
    else 'pending'
  end,
    'email', i."email",
    'role', i."role_id",
    'tenant', i."organization_id",
    'expires_at', i."expires_at",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "centrakit"."organizations" o where o."id" = i."organization_id"),
    'prefill', i."prefill"
  ), i."id"
  into preview, invitation
  from "centrakit"."organization_invitations" i
  where i."token" = invitation_preview.token and i."organization_id" is not null;
  if preview is null then
    select jsonb_build_object(
    'status', case
    when i."accepted_at" is not null then 'accepted'
    when i."declined_at" is not null then 'declined'
    when i."expires_at" < now() then 'expired'
    else 'pending'
  end,
    'email', i."email",
    'role', i."role_id",
    'tenant', null,
    'expires_at', i."expires_at",
    'organization', null,
    'prefill', i."prefill"
  ), i."id"
    into preview, invitation
    from "centrakit"."organization_invitations" i
    where i."token" = invitation_preview.token and i."organization_id" is null;
  end if;
  if preview is not null then
    preview := preview || "better_supabase"."invitation_extra"(invitation);
  end if;
  return preview;
end;
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
  invite "centrakit"."organization_invitations";
  pinvite "centrakit"."organization_invitations";
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "centrakit"."organization_invitations" i
  where i."token" = token and i."organization_id" is not null
  for update;
  if invite."id" is null then
  select * into pinvite
  from "centrakit"."organization_invitations" i
  where i."token" = token and i."organization_id" is null
  for update;
  if pinvite."id" is not null then
  if not (pinvite."accepted_at" is null and pinvite."declined_at" is null) then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if pinvite."expires_at" < now() then
    raise exception 'The invitation has expired; ask for a new one' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  if lower(pinvite."email") <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(pinvite."email")
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  if pinvite."invited_by" = me then
    raise exception 'You cannot accept your own invitation' using errcode = '42501', hint = 'INVITATION_SELF';
  end if;
  if pinvite."invited_by" is not null and not (
    coalesce(better_supabase.platform_can(pinvite."invited_by", 'platform.invite'), false)
  ) then
    raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
  end if;
  if (select r."id" from "centrakit"."roles" r where (r."id"::text = (pinvite."role_id")::text or r."key"::text = (pinvite."role_id")::text) and (r.scope = 'system') order by (r."id"::text = (pinvite."role_id")::text) desc limit 1) is null then
    raise exception 'Unknown platform role %', pinvite."role_id" using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  insert into "centrakit"."user_roles" ("user_id", "role_id")
  values (me, (select r."id" from "centrakit"."roles" r where (r."id"::text = (pinvite."role_id")::text or r."key"::text = (pinvite."role_id")::text) and (r.scope = 'system') order by (r."id"::text = (pinvite."role_id")::text) desc limit 1))
  on conflict do nothing;
  update "centrakit"."organization_invitations"
  set "accepted_at" = now()
  where "id" = pinvite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using pinvite."id", me;
    end if;
  end;
  perform "better_supabase".emit_event('invitation.accepted', jsonb_build_object('invitationId', pinvite."id", 'organizationId', null, 'email', pinvite."email", 'role', pinvite."role_id"), 'invitations/' || pinvite."id"::text, null, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => pinvite."id"::text,
    metadata => jsonb_build_object('invitationId', pinvite."id", 'organizationId', null, 'email', pinvite."email", 'role', pinvite."role_id")
  );
  return null;
  end if;
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invite."accepted_at" is null and invite."declined_at" is null) then
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
  if better_supabase.tenant_disabled(invite."organization_id") or not exists (select 1 from "centrakit"."organizations" o where o."id" = invite."organization_id") then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "centrakit"."organization_users" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", (select r."key"::text from "centrakit"."roles" r where r."id"::text = (invite."role_id")::text)) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  if (select r."id" from "centrakit"."roles" r where (r."id"::text = (invite."role_id")::text or r."key"::text = (invite."role_id")::text) and (r.scope = 'organization') order by (r."id"::text = (invite."role_id")::text) desc limit 1) is null then
    raise exception 'Unknown role %', invite."role_id" using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  insert into "centrakit"."organization_users" ("organization_id", "user_id", "role_id")
  values (invite."organization_id", me, (select r."id" from "centrakit"."roles" r where (r."id"::text = (invite."role_id")::text or r."key"::text = (invite."role_id")::text) and (r.scope = 'organization') order by (r."id"::text = (invite."role_id")::text) desc limit 1));
  update "centrakit"."organization_invitations"
  set "accepted_at" = now()
  where "id" = invite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using invite."id", me;
    end if;
  end;
  perform "better_supabase".emit_event('invitation.accepted', jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role_id"), 'invitations/' || invite."id"::text, (invite."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => invite."id"::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role_id")
  );
  perform "better_supabase".emit_event('organization.member_added', jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role_id"), 'organizations/' || invite."organization_id"::text, (invite."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'organization.member_added',
    category => 'membership',
    target_type => 'user',
    record_id => me::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role_id")
  );
  return invite."organization_id";
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
  invite "centrakit"."organization_invitations";
  pinvite "centrakit"."organization_invitations";
begin
  if not (centrakit.authz_actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "centrakit"."organization_invitations" i
  where i."id" = invitation_id and i."organization_id" is not null
  for update;
  if invite."id" is null then
  select * into pinvite
  from "centrakit"."organization_invitations" i
  where i."id" = invitation_id and i."organization_id" is null
  for update;
  if pinvite."id" is not null then
  if not (pinvite."accepted_at" is null and pinvite."declined_at" is null) then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if pinvite."expires_at" < now() then
    raise exception 'The invitation has expired; ask for a new one' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  if lower(pinvite."email") <> lower(coalesce(auth.jwt() ->> 'email', '')) then
    raise exception 'The invitation is for another email address' using errcode = '42501', hint = 'INVITATION_EMAIL_MISMATCH';
  end if;
  -- The email claim alone does not prove the address: an unconfirmed sign-up carries it too.
  if not exists (
    select 1 from auth.users u
    where u.id = me and u.email_confirmed_at is not null and lower(u.email) = lower(pinvite."email")
  ) then
    raise exception 'Confirm your email address before accepting the invitation' using errcode = '42501', hint = 'INVITATION_EMAIL_UNCONFIRMED';
  end if;
  if pinvite."invited_by" = me then
    raise exception 'You cannot accept your own invitation' using errcode = '42501', hint = 'INVITATION_SELF';
  end if;
  if pinvite."invited_by" is not null and not (
    coalesce(better_supabase.platform_can(pinvite."invited_by", 'platform.invite'), false)
  ) then
    raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
  end if;
  if (select r."id" from "centrakit"."roles" r where (r."id"::text = (pinvite."role_id")::text or r."key"::text = (pinvite."role_id")::text) and (r.scope = 'system') order by (r."id"::text = (pinvite."role_id")::text) desc limit 1) is null then
    raise exception 'Unknown platform role %', pinvite."role_id" using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  insert into "centrakit"."user_roles" ("user_id", "role_id")
  values (me, (select r."id" from "centrakit"."roles" r where (r."id"::text = (pinvite."role_id")::text or r."key"::text = (pinvite."role_id")::text) and (r.scope = 'system') order by (r."id"::text = (pinvite."role_id")::text) desc limit 1))
  on conflict do nothing;
  update "centrakit"."organization_invitations"
  set "accepted_at" = now()
  where "id" = pinvite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using pinvite."id", me;
    end if;
  end;
  perform "better_supabase".emit_event('invitation.accepted', jsonb_build_object('invitationId', pinvite."id", 'organizationId', null, 'email', pinvite."email", 'role', pinvite."role_id"), 'invitations/' || pinvite."id"::text, null, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => pinvite."id"::text,
    metadata => jsonb_build_object('invitationId', pinvite."id", 'organizationId', null, 'email', pinvite."email", 'role', pinvite."role_id")
  );
  return null;
  end if;
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if not (invite."accepted_at" is null and invite."declined_at" is null) then
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
  if better_supabase.tenant_disabled(invite."organization_id") or not exists (select 1 from "centrakit"."organizations" o where o."id" = invite."organization_id") then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "centrakit"."organization_users" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", (select r."key"::text from "centrakit"."roles" r where r."id"::text = (invite."role_id")::text)) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  if (select r."id" from "centrakit"."roles" r where (r."id"::text = (invite."role_id")::text or r."key"::text = (invite."role_id")::text) and (r.scope = 'organization') order by (r."id"::text = (invite."role_id")::text) desc limit 1) is null then
    raise exception 'Unknown role %', invite."role_id" using errcode = '23514', hint = 'INVITATION_ROLE_UNKNOWN';
  end if;
  insert into "centrakit"."organization_users" ("organization_id", "user_id", "role_id")
  values (invite."organization_id", me, (select r."id" from "centrakit"."roles" r where (r."id"::text = (invite."role_id")::text or r."key"::text = (invite."role_id")::text) and (r.scope = 'organization') order by (r."id"::text = (invite."role_id")::text) desc limit 1));
  update "centrakit"."organization_invitations"
  set "accepted_at" = now()
  where "id" = invite."id";
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invitation_accept"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using invite."id", me;
    end if;
  end;
  perform "better_supabase".emit_event('invitation.accepted', jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role_id"), 'invitations/' || invite."id"::text, (invite."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => invite."id"::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role_id")
  );
  perform "better_supabase".emit_event('organization.member_added', jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role_id"), 'organizations/' || invite."organization_id"::text, (invite."organization_id")::text, null, 'domain');
  perform better_supabase.audit_event(
    event_type => 'organization.member_added',
    category => 'membership',
    target_type => 'user',
    record_id => me::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role_id")
  );
  return invite."organization_id";
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
    'tenant', i."organization_id",
    'email', i."email",
    'role', i."role_id",
    'expires_at', i."expires_at",
    'created_at', i."created_at",
    'invited_by', i."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "centrakit"."organizations" o where o."id" = i."organization_id"),
    'prefill', i."prefill",
    'inviter', (select jsonb_build_object('id', pr."user_id", 'username', pr."username", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_path")
      from "centrakit"."profiles" pr where pr."user_id" = i."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(i."id")) - 'token' as invitation, i."id" as id, i."expires_at" as expires_at
    from "centrakit"."organization_invitations" i
    where lower(i."email") = invitee_email
      and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is not null
    union all
    select (jsonb_build_object(
    'id', i."id",
    'tenant', null,
    'email', i."email",
    'role', i."role_id",
    'expires_at', i."expires_at",
    'created_at', i."created_at",
    'invited_by', i."invited_by",
    'organization', null,
    'prefill', i."prefill",
    'inviter', (select jsonb_build_object('id', pr."user_id", 'username', pr."username", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_path")
      from "centrakit"."profiles" pr where pr."user_id" = i."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(i."id")) - 'token' as invitation, i."id" as id, i."expires_at" as expires_at
    from "centrakit"."organization_invitations" i
    where lower(i."email") = invitee_email
      and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."organization_id" is null
  ) x;
  return result;
end;
$$;

revoke execute on function "better_supabase"."invite_member"(uuid, text, text, interval, jsonb) from public, anon;
grant execute on function "better_supabase"."invite_member"(uuid, text, text, interval, jsonb) to authenticated, service_role;
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "centrakit"."organization_invitations";
create policy bsb_tenant_scope on "centrakit"."organization_invitations" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select "better_supabase"."invitation_tenant_ids"()))
    or ("organization_id" in (select "better_supabase"."invitation_tenant_ids"()) or (select "better_supabase"."platform_invitations_readable"()))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
