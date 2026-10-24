-- ==== alone: schema supabase/schemas/900_better_supabase_005_invitations.sql
-- better-supabase module: invitations
-- @bsb-block invitations@2 managed
-- @bsb-hash sha256:8a86cb5092e3d8b44aa90e102768ebe2f64e820f06d8fa07f4f684f4cb178dde
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."invitations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists "better_supabase"."invitations" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "email" text not null,
  "role" text not null,
  "token_hash" text not null unique,
  "expires_at" timestamptz not null,
  "accepted_at" timestamptz
);
alter table "better_supabase"."invitations" alter column "organization_id" set not null;
alter table "better_supabase"."invitations" alter column "role" drop default;
alter table "better_supabase"."invitations" add column if not exists "invited_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."invitations" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."invitations" add column if not exists "accepted_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."invitations" add column if not exists "declined_at" timestamptz;
alter table "better_supabase"."invitations" add column if not exists "revoked_at" timestamptz;

drop index if exists "better_supabase".invitations_open_idx;
create unique index if not exists invitations_open_email_idx
  on "better_supabase"."invitations" ("organization_id", lower("email")) where "accepted_at" is null and "declined_at" is null and "revoked_at" is null;
create index if not exists invitations_tenant_created_idx on "better_supabase"."invitations" ("organization_id", "created_at");
alter table "better_supabase"."invitations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."invitations";
create trigger bsb_updated_at before update on "better_supabase"."invitations"
  for each row execute function better_supabase.set_updated_at('updated_at');
create index if not exists invitations_invited_by_idx on "better_supabase"."invitations" ("invited_by");
create index if not exists invitations_accepted_by_idx on "better_supabase"."invitations" ("accepted_by");

alter table "better_supabase"."invitations" drop constraint if exists invitations_role_check;
alter table "better_supabase"."invitations"
  add constraint invitations_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

alter table "better_supabase"."invitations" enable row level security;
revoke all on "better_supabase"."invitations" from anon, authenticated;
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
drop policy if exists bsb_invitations_read on "better_supabase"."invitations";
create policy bsb_invitations_read on "better_supabase"."invitations" for select to authenticated
  using ("organization_id" in (select "better_supabase"."invitation_tenant_ids"()));

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
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or false then
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
  where i."organization_id" = tenant
    and lower(i."email") = lower(btrim(invitee_email))
    and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  insert into "better_supabase"."invitations" ("organization_id", "email", "role", "token_hash", "invited_by", "expires_at")
  values (tenant, lower(btrim(invitee_email)), invitee_role, encode(extensions.digest(token, 'sha256'), 'hex'), auth.uid(), now() + valid_for)
  returning * into created;
  null;
  return (jsonb_build_object(
    'id', created."id",
    'tenant', created."organization_id",
    'email', created."email",
    'role', created."role",
    'expires_at', created."expires_at",
    'created_at', created."created_at",
    'invited_by', created."invited_by",
    'organization', jsonb_build_object('id', created."organization_id"),
    'prefill', '{}'::jsonb,
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
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false))
  returning * into updated;
  if updated."id" is null then
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  null;
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', jsonb_build_object('id', updated."organization_id"),
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
  tenant := current_invite."organization_id";
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or false then
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
    where i."organization_id" = tenant
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
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', jsonb_build_object('id', updated."organization_id"),
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
  update "better_supabase"."invitations" i set "revoked_at" = now() where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false)) and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."organization_id"::text into tenant;
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
  returning i."id", i."organization_id"::text into declined_id, tenant;
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
  returning i."id", i."organization_id"::text into declined_id, tenant;
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
    'tenant', i."organization_id",
    'expires_at', i."expires_at",
    'organization', jsonb_build_object('id', i."organization_id"),
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
  if better_supabase.tenant_disabled(invite."organization_id") or false then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
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
  if better_supabase.tenant_disabled(invite."organization_id") or false then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
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
    'role', i."role",
    'expires_at', i."expires_at",
    'created_at', i."created_at",
    'invited_by', i."invited_by",
    'organization', jsonb_build_object('id', i."organization_id"),
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

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
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
drop policy if exists bsb_tenant_scope on "better_supabase"."invitations";
create policy bsb_tenant_scope on "better_supabase"."invitations" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select "better_supabase"."invitation_tenant_ids"()))
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_005_invitations.sql
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

-- ==== with every module: schema supabase/schemas/900_better_supabase_005_invitations.sql
-- better-supabase module: invitations
-- @bsb-block invitations@2 managed
-- @bsb-hash sha256:1594822ddf08768c1b06c8c963e79b83660e6fc08dac884f7a7b963cdad25bf5
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."invitations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists "better_supabase"."invitations" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "email" text not null,
  "role" text not null,
  "token_hash" text not null unique,
  "expires_at" timestamptz not null,
  "accepted_at" timestamptz
);
alter table "better_supabase"."invitations" alter column "organization_id" set not null;
alter table "better_supabase"."invitations" alter column "role" drop default;
alter table "better_supabase"."invitations" add column if not exists "invited_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."invitations" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."invitations" add column if not exists "accepted_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."invitations" add column if not exists "declined_at" timestamptz;
alter table "better_supabase"."invitations" add column if not exists "revoked_at" timestamptz;

drop index if exists "better_supabase".invitations_open_idx;
create unique index if not exists invitations_open_email_idx
  on "better_supabase"."invitations" ("organization_id", lower("email")) where "accepted_at" is null and "declined_at" is null and "revoked_at" is null;
create index if not exists invitations_tenant_created_idx on "better_supabase"."invitations" ("organization_id", "created_at");
alter table "better_supabase"."invitations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."invitations";
create trigger bsb_updated_at before update on "better_supabase"."invitations"
  for each row execute function better_supabase.set_updated_at('updated_at');
create index if not exists invitations_invited_by_idx on "better_supabase"."invitations" ("invited_by");
create index if not exists invitations_accepted_by_idx on "better_supabase"."invitations" ("accepted_by");

alter table "better_supabase"."invitations" drop constraint if exists invitations_role_check;
alter table "better_supabase"."invitations"
  add constraint invitations_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

alter table "better_supabase"."invitations" enable row level security;
revoke all on "better_supabase"."invitations" from anon, authenticated;
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
drop policy if exists bsb_invitations_read on "better_supabase"."invitations";
create policy bsb_invitations_read on "better_supabase"."invitations" for select to authenticated
  using ("organization_id" in (select "better_supabase"."invitation_tenant_ids"()));

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
  where i."organization_id" = tenant
    and lower(i."email") = lower(btrim(invitee_email))
    and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  insert into "better_supabase"."invitations" ("organization_id", "email", "role", "token_hash", "invited_by", "expires_at")
  values (tenant, lower(btrim(invitee_email)), invitee_role, encode(extensions.digest(token, 'sha256'), 'hex'), auth.uid(), now() + valid_for)
  returning * into created;
  perform "better_supabase".emit_event('invitation.created', jsonb_build_object('invitationId', created."id", 'organizationId', tenant::text, 'email', created."email", 'role', created."role"), 'invitations/' || created."id"::text, (tenant)::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.created',
    category => 'membership',
    target_type => 'invitation',
    record_id => created."id"::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', created."id", 'organizationId', tenant::text, 'email', created."email", 'role', created."role")
  );
  return (jsonb_build_object(
    'id', created."id",
    'tenant', created."organization_id",
    'email', created."email",
    'role', created."role",
    'expires_at', created."expires_at",
    'created_at', created."created_at",
    'invited_by', created."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "better_supabase"."organizations" o where o."id" = created."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = created."invited_by"),
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
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false))
  returning * into updated;
  if updated."id" is null then
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  perform "better_supabase".emit_event('invitation.resent', jsonb_build_object('invitationId', updated."id", 'organizationId', updated."organization_id"::text, 'email', updated."email"), 'invitations/' || updated."id"::text, (updated."organization_id")::text, null, 'better-supabase/invitations');
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
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "better_supabase"."organizations" o where o."id" = updated."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = updated."invited_by"),
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
  tenant := current_invite."organization_id";
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
    where i."organization_id" = tenant
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
  perform "better_supabase".emit_event('invitation.updated', jsonb_build_object('invitationId', updated."id", 'organizationId', tenant::text, 'email', updated."email", 'role', updated."role"), 'invitations/' || updated."id"::text, (tenant)::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.updated',
    category => 'membership',
    target_type => 'invitation',
    record_id => updated."id"::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('invitationId', updated."id", 'organizationId', tenant::text, 'email', updated."email", 'role', updated."role")
  );
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "better_supabase"."organizations" o where o."id" = updated."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = updated."invited_by"),
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
  update "better_supabase"."invitations" i set "revoked_at" = now() where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false)) and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."organization_id"::text into tenant;
  if found then
    perform "better_supabase".emit_event('invitation.revoked', jsonb_build_object('invitationId', invitation_id, 'organizationId', tenant), 'invitations/' || invitation_id::text, (tenant)::text, null, 'better-supabase/invitations');
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
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
    perform "better_supabase".emit_event('invitation.declined', jsonb_build_object('invitationId', declined_id, 'organizationId', tenant), 'invitations/' || declined_id::text, (tenant)::text, null, 'better-supabase/invitations');
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
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
    perform "better_supabase".emit_event('invitation.declined', jsonb_build_object('invitationId', declined_id, 'organizationId', tenant), 'invitations/' || declined_id::text, (tenant)::text, null, 'better-supabase/invitations');
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
    'tenant', i."organization_id",
    'expires_at', i."expires_at",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "better_supabase"."organizations" o where o."id" = i."organization_id"),
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
  if better_supabase.tenant_disabled(invite."organization_id") or not exists (select 1 from "better_supabase"."organizations" o where o."id" = invite."organization_id") then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
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
  perform "better_supabase".emit_event('invitation.accepted', jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role"), 'invitations/' || invite."id"::text, (invite."organization_id")::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => invite."id"::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role")
  );
  perform "better_supabase".emit_event('organization.member_added', jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role"), 'organizations/' || invite."organization_id"::text, (invite."organization_id")::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'organization.member_added',
    category => 'membership',
    target_type => 'user',
    record_id => me::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role")
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
  if better_supabase.tenant_disabled(invite."organization_id") or not exists (select 1 from "better_supabase"."organizations" o where o."id" = invite."organization_id") then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
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
  perform "better_supabase".emit_event('invitation.accepted', jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role"), 'invitations/' || invite."id"::text, (invite."organization_id")::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'invitation.accepted',
    category => 'membership',
    target_type => 'invitation',
    record_id => invite."id"::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('invitationId', invite."id", 'organizationId', invite."organization_id"::text, 'email', invite."email", 'role', invite."role")
  );
  perform "better_supabase".emit_event('organization.member_added', jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role"), 'organizations/' || invite."organization_id"::text, (invite."organization_id")::text, null, 'better-supabase/invitations');
  perform better_supabase.audit_event(
    event_type => 'organization.member_added',
    category => 'membership',
    target_type => 'user',
    record_id => me::text,
    tenant => (invite."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', invite."organization_id"::text, 'userId', me, 'role', invite."role")
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
    'role', i."role",
    'expires_at', i."expires_at",
    'created_at', i."created_at",
    'invited_by', i."invited_by",
    'organization', (select jsonb_build_object('id', o."id", 'name', o."name")
      from "better_supabase"."organizations" o where o."id" = i."organization_id"),
    'prefill', '{}'::jsonb,
    'inviter', (select jsonb_build_object('id', pr."id", 'username', pr."username", 'fullName', pr."full_name", 'firstName', pr."first_name", 'lastName', pr."last_name", 'avatar', pr."avatar_url")
      from "better_supabase"."profiles" pr where pr."id" = i."invited_by"),
    'token', null
  ) || "better_supabase"."invitation_extra"(i."id")) - 'token' as invitation, i."id" as id, i."expires_at" as expires_at
    from "better_supabase"."invitations" i
    where lower(i."email") = invitee_email
      and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
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

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
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
drop policy if exists bsb_tenant_scope on "better_supabase"."invitations";
create policy bsb_tenant_scope on "better_supabase"."invitations" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select "better_supabase"."invitation_tenant_ids"()))
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_005_invitations.sql
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

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_005_invitations.sql
-- better-supabase module: invitations
-- @bsb-block invitations@2 managed
-- @bsb-hash sha256:533710feb3be2b9420cba9310404f204adb6fee49e119b6b44abc96b6ec3794e
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
    drop policy if exists bsb_tenant_scope on "app_private"."invitations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;

create table if not exists "app_private"."invitations" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "email" text not null,
  "role" text not null,
  "token_hash" text not null unique,
  "expires_at" timestamptz not null,
  "accepted_at" timestamptz
);
alter table "app_private"."invitations" alter column "organization_id" set not null;
alter table "app_private"."invitations" alter column "role" drop default;
alter table "app_private"."invitations" add column if not exists "invited_by" uuid references auth.users (id) on delete set null;
alter table "app_private"."invitations" add column if not exists "created_at" timestamptz not null default now();
alter table "app_private"."invitations" add column if not exists "accepted_by" uuid references auth.users (id) on delete set null;
alter table "app_private"."invitations" add column if not exists "declined_at" timestamptz;
alter table "app_private"."invitations" add column if not exists "revoked_at" timestamptz;

drop index if exists "app_private".invitations_open_idx;
create unique index if not exists invitations_open_email_idx
  on "app_private"."invitations" ("organization_id", lower("email")) where "accepted_at" is null and "declined_at" is null and "revoked_at" is null;
create index if not exists invitations_tenant_created_idx on "app_private"."invitations" ("organization_id", "created_at");
alter table "app_private"."invitations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "app_private"."invitations";
create trigger bsb_updated_at before update on "app_private"."invitations"
  for each row execute function better_supabase.set_updated_at('updated_at');
create index if not exists invitations_invited_by_idx on "app_private"."invitations" ("invited_by");
create index if not exists invitations_accepted_by_idx on "app_private"."invitations" ("accepted_by");

alter table "app_private"."invitations" drop constraint if exists invitations_role_check;
alter table "app_private"."invitations"
  add constraint invitations_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

alter table "app_private"."invitations" enable row level security;
revoke all on "app_private"."invitations" from anon, authenticated;
grant select on "app_private"."invitations" to authenticated;
grant all on "app_private"."invitations" to service_role;

-- PL/pgSQL resolves tenant_ids_with when it runs, so this file installs
-- before the access module's.
create or replace function "app_private"."invitation_tenant_ids"()
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
revoke execute on function "app_private"."invitation_tenant_ids"() from public, anon;
grant execute on function "app_private"."invitation_tenant_ids"() to authenticated, service_role;
drop policy if exists bsb_invitations_read on "app_private"."invitations";
create policy bsb_invitations_read on "app_private"."invitations" for select to authenticated
  using ("organization_id" in (select "app_private"."invitation_tenant_ids"()));

-- The keys an invitation_preview_extra(invitation uuid) hook returns for an
-- invitation, such as a role's display name; {} without the hook. The
-- module's functions merge them into every invitation they return.
create or replace function "app_private"."invitation_extra"(invitation uuid)
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
revoke execute on function "app_private"."invitation_extra"(uuid) from public, anon, authenticated;

-- Invites email to tenant (null: a platform invitation) with role, a catalog
-- role id or key under blocks.permissions.model 'catalog'. Returns the invitation
-- and its token; only the token's hash is stored. An open invitation for
-- the same email is replaced.
drop function if exists "app_private"."invite_member"(uuid, text, text, interval, jsonb, jsonb);
create or replace function "app_private"."invite_member"(
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
  created "app_private"."invitations";
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
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or false then
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
  delete from "app_private"."invitations" i
  where i."organization_id" = tenant
    and lower(i."email") = lower(btrim(invitee_email))
    and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  insert into "app_private"."invitations" ("organization_id", "email", "role", "token_hash", "invited_by", "expires_at")
  values (tenant, lower(btrim(invitee_email)), invitee_role, encode(extensions.digest(token, 'sha256'), 'hex'), auth.uid(), now() + valid_for)
  returning * into created;
  null;
  return (jsonb_build_object(
    'id', created."id",
    'tenant', created."organization_id",
    'email', created."email",
    'role', created."role",
    'expires_at', created."expires_at",
    'created_at', created."created_at",
    'invited_by', created."invited_by",
    'organization', jsonb_build_object('id', created."organization_id"),
    'prefill', '{}'::jsonb,
    'token', token
  ) || "app_private"."invitation_extra"(created."id"));
end;
$$;

-- The 0.4 signature: returns the token only.
drop function if exists "app_private"."create_invitation"(uuid, text, text, interval);
create or replace function "app_private"."create_invitation"(
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
  select "app_private"."invite_member"($1, $2, $3, $4) ->> 'token'
$$;

-- A new token and expiry for an open invitation; the old token stops working.
create or replace function "app_private"."resend_invitation"(invitation_id uuid, valid_for interval default '7 days')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  token text := encode(extensions.gen_random_bytes(24), 'hex');
  updated "app_private"."invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if valid_for is null or valid_for <= interval '0' or valid_for > '30 days'::interval then
    raise exception 'An invitation is valid for at most %', '30 days' using errcode = '22023', hint = 'INVITATION_VALIDITY';
  end if;
  update "app_private"."invitations" i
  set "token_hash" = encode(extensions.digest(token, 'sha256'), 'hex'),
    "expires_at" = now() + valid_for
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false))
  returning * into updated;
  if updated."id" is null then
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  null;
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', jsonb_build_object('id', updated."organization_id"),
    'prefill', '{}'::jsonb,
    'token', token
  ) || "app_private"."invitation_extra"(updated."id"));
end;
$$;

-- A new email, role or prefill for an open invitation that has not expired;
-- null keeps the current value. The caller needs what invite_member needs, and may assign
-- both the current and the new role. The token and expiry stay, and another
-- open invitation for the new email is replaced. Returns the invitation
-- without its token.
create or replace function "app_private"."update_invitation"(
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
  current_invite "app_private"."invitations";
  updated "app_private"."invitations";
  tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if invitee_email is not null and btrim(invitee_email) = '' then
    raise exception 'The email address is empty' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  select * into current_invite from "app_private"."invitations" i
  where i."id" = invitation_id and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  for update;
  if current_invite."id" is null then
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if current_invite."expires_at" < now() then
    raise exception 'The invitation has expired; resend it to renew it' using errcode = 'P0002', hint = 'INVITATION_EXPIRED';
  end if;
  tenant := current_invite."organization_id";
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or false then
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
    delete from "app_private"."invitations" i
    where i."organization_id" = tenant
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
    update "app_private"."invitations" i
    set "email" = updated."email",
      "role" = updated."role"
    where i."id" = invitation_id
    returning * into updated;
  null;
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', jsonb_build_object('id', updated."organization_id"),
    'prefill', '{}'::jsonb,
    'token', null
  ) || "app_private"."invitation_extra"(updated."id")) - 'token';
end;
$$;

-- Revokes an open invitation (deletes it when revokedAt is mapped to null).
create or replace function "app_private"."revoke_invitation"(invitation_id uuid)
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
  update "app_private"."invitations" i set "revoked_at" = now() where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false)) and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."organization_id"::text into tenant;
  if found then
    null;
    return true;
  end if;
  return false;
end;
$$;

-- The invitee declines with the token, signed in or not.
create or replace function "app_private"."decline_invitation"(token text)
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
  update "app_private"."invitations" i set "declined_at" = now() where i."token_hash" = encode(extensions.digest(token, 'sha256'), 'hex') and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id", i."organization_id"::text into declined_id, tenant;
  if declined_id is not null then
    null;
    return true;
  end if;
  return false;
end;
$$;

create or replace function "app_private"."decline_invitation_by_id"(invitation_id uuid)
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
  update "app_private"."invitations" i set "declined_at" = now() where i."id" = invitation_id and lower(i."email") = invitee_email and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."id", i."organization_id"::text into declined_id, tenant;
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
create or replace function "app_private"."invitation_preview"(token text)
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
    'tenant', i."organization_id",
    'expires_at', i."expires_at",
    'organization', jsonb_build_object('id', i."organization_id"),
    'prefill', '{}'::jsonb
  ), i."id"
  into preview, invitation
  from "app_private"."invitations" i
  where i."token_hash" = encode(extensions.digest(invitation_preview.token, 'sha256'), 'hex');
  if preview is not null then
    preview := preview || "app_private"."invitation_extra"(invitation);
  end if;
  return preview;
end;
$$;

-- Accepts with the token for the signed-in user, whose confirmed email must
-- match, and returns the tenant (null for a platform invitation).
create or replace function "app_private"."accept_invitation"(token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
  invite "app_private"."invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "app_private"."invitations" i
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
  if better_supabase.tenant_disabled(invite."organization_id") or false then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
  update "app_private"."invitations"
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
  return invite."organization_id";
end;
$$;

create or replace function "app_private"."accept_invitation_by_id"(invitation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  me uuid := auth.uid();
  invite "app_private"."invitations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if me is null then
    raise exception 'Sign in to accept an invitation' using errcode = '42501', hint = 'INVITATION_SIGN_IN';
  end if;
  select * into invite
  from "app_private"."invitations" i
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
  if better_supabase.tenant_disabled(invite."organization_id") or false then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
  update "app_private"."invitations"
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
  return invite."organization_id";
end;
$$;

-- The caller's open invitations, for an in-app inbox: the invitation without
-- its token, its organization (id plus previewColumns) and the keys an
-- invitation_preview_extra(invitation uuid) hook adds.
create or replace function "app_private"."my_invitations"()
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
    'role', i."role",
    'expires_at', i."expires_at",
    'created_at', i."created_at",
    'invited_by', i."invited_by",
    'organization', jsonb_build_object('id', i."organization_id"),
    'prefill', '{}'::jsonb,
    'token', null
  ) || "app_private"."invitation_extra"(i."id")) - 'token' as invitation, i."id" as id, i."expires_at" as expires_at
    from "app_private"."invitations" i
    where lower(i."email") = invitee_email
      and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  ) x;
  return result;
end;
$$;

revoke execute on function "app_private"."invite_member"(uuid, text, text, interval, jsonb) from public, anon;
grant execute on function "app_private"."invite_member"(uuid, text, text, interval, jsonb) to authenticated, service_role;
revoke execute on function "app_private"."create_invitation"(uuid, text, text, interval) from public, anon;
grant execute on function "app_private"."create_invitation"(uuid, text, text, interval) to authenticated, service_role;
revoke execute on function "app_private"."resend_invitation"(uuid, interval) from public, anon;
grant execute on function "app_private"."resend_invitation"(uuid, interval) to authenticated, service_role;
revoke execute on function "app_private"."update_invitation"(uuid, text, text, jsonb) from public, anon;
grant execute on function "app_private"."update_invitation"(uuid, text, text, jsonb) to authenticated, service_role;
revoke execute on function "app_private"."revoke_invitation"(uuid) from public, anon;
grant execute on function "app_private"."revoke_invitation"(uuid) to authenticated, service_role;
revoke execute on function "app_private"."decline_invitation"(text) from public;
grant execute on function "app_private"."decline_invitation"(text) to anon, authenticated, service_role;
revoke execute on function "app_private"."invitation_preview"(text) from public;
grant execute on function "app_private"."invitation_preview"(text) to anon, authenticated, service_role;
revoke execute on function "app_private"."accept_invitation"(text) from public, anon;
grant execute on function "app_private"."accept_invitation"(text) to authenticated;
revoke execute on function "app_private"."accept_invitation_by_id"(uuid) from public, anon;
grant execute on function "app_private"."accept_invitation_by_id"(uuid) to authenticated;
revoke execute on function "app_private"."decline_invitation_by_id"(uuid) from public, anon;
grant execute on function "app_private"."decline_invitation_by_id"(uuid) to authenticated;
revoke execute on function "app_private"."my_invitations"() from public, anon;
grant execute on function "app_private"."my_invitations"() to authenticated;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
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
drop policy if exists bsb_tenant_scope on "app_private"."invitations";
create policy bsb_tenant_scope on "app_private"."invitations" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select "app_private"."invitation_tenant_ids"()))
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_005_invitations.sql
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

-- ==== api schema: schema supabase/schemas/900_better_supabase_005_invitations.sql
-- better-supabase module: invitations
-- @bsb-block invitations@2 managed
-- @bsb-hash sha256:5539280ee035fbd43b6aa5e29aa76d6a50bc9c87e87a890d165cfd767ec57ce9
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."invitations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

create table if not exists "better_supabase"."invitations" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "email" text not null,
  "role" text not null,
  "token_hash" text not null unique,
  "expires_at" timestamptz not null,
  "accepted_at" timestamptz
);
alter table "better_supabase"."invitations" alter column "organization_id" set not null;
alter table "better_supabase"."invitations" alter column "role" drop default;
alter table "better_supabase"."invitations" add column if not exists "invited_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."invitations" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."invitations" add column if not exists "accepted_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."invitations" add column if not exists "declined_at" timestamptz;
alter table "better_supabase"."invitations" add column if not exists "revoked_at" timestamptz;

drop index if exists "better_supabase".invitations_open_idx;
create unique index if not exists invitations_open_email_idx
  on "better_supabase"."invitations" ("organization_id", lower("email")) where "accepted_at" is null and "declined_at" is null and "revoked_at" is null;
create index if not exists invitations_tenant_created_idx on "better_supabase"."invitations" ("organization_id", "created_at");
alter table "better_supabase"."invitations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."invitations";
create trigger bsb_updated_at before update on "better_supabase"."invitations"
  for each row execute function better_supabase.set_updated_at('updated_at');
create index if not exists invitations_invited_by_idx on "better_supabase"."invitations" ("invited_by");
create index if not exists invitations_accepted_by_idx on "better_supabase"."invitations" ("accepted_by");

alter table "better_supabase"."invitations" drop constraint if exists invitations_role_check;
alter table "better_supabase"."invitations"
  add constraint invitations_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

alter table "better_supabase"."invitations" enable row level security;
revoke all on "better_supabase"."invitations" from anon, authenticated;
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
drop policy if exists bsb_invitations_read on "better_supabase"."invitations";
create policy bsb_invitations_read on "better_supabase"."invitations" for select to authenticated
  using ("organization_id" in (select "better_supabase"."invitation_tenant_ids"()));

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
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or false then
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
  where i."organization_id" = tenant
    and lower(i."email") = lower(btrim(invitee_email))
    and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  insert into "better_supabase"."invitations" ("organization_id", "email", "role", "token_hash", "invited_by", "expires_at")
  values (tenant, lower(btrim(invitee_email)), invitee_role, encode(extensions.digest(token, 'sha256'), 'hex'), auth.uid(), now() + valid_for)
  returning * into created;
  null;
  return (jsonb_build_object(
    'id', created."id",
    'tenant', created."organization_id",
    'email', created."email",
    'role', created."role",
    'expires_at', created."expires_at",
    'created_at', created."created_at",
    'invited_by', created."invited_by",
    'organization', jsonb_build_object('id', created."organization_id"),
    'prefill', '{}'::jsonb,
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
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false))
  returning * into updated;
  if updated."id" is null then
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  null;
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', jsonb_build_object('id', updated."organization_id"),
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
  tenant := current_invite."organization_id";
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or false then
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
    where i."organization_id" = tenant
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
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', jsonb_build_object('id', updated."organization_id"),
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
  update "better_supabase"."invitations" i set "revoked_at" = now() where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false)) and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."organization_id"::text into tenant;
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
  returning i."id", i."organization_id"::text into declined_id, tenant;
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
  returning i."id", i."organization_id"::text into declined_id, tenant;
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
    'tenant', i."organization_id",
    'expires_at', i."expires_at",
    'organization', jsonb_build_object('id', i."organization_id"),
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
  if better_supabase.tenant_disabled(invite."organization_id") or false then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
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
  if better_supabase.tenant_disabled(invite."organization_id") or false then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
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
    'role', i."role",
    'expires_at', i."expires_at",
    'created_at', i."created_at",
    'invited_by', i."invited_by",
    'organization', jsonb_build_object('id', i."organization_id"),
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

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
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
drop policy if exists bsb_tenant_scope on "better_supabase"."invitations";
create policy bsb_tenant_scope on "better_supabase"."invitations" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select "better_supabase"."invitation_tenant_ids"()))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

-- blocks.invitations.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.
drop function if exists "api"."invitation_tenant_ids"();

drop function if exists "api"."invite_member"(uuid, text, text, interval, jsonb, jsonb);
drop function if exists "api"."create_invitation"(uuid, text, text, interval);

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

create or replace function "api"."invite_member"(tenant uuid, invitee_email text, invitee_role text, valid_for interval default '7 days', prefill jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."invite_member"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."invite_member"(uuid, text, text, interval, jsonb) from public, anon;
grant execute on function "api"."invite_member"(uuid, text, text, interval, jsonb) to authenticated, service_role;

create or replace function "api"."create_invitation"(organization uuid, invitee_email text, invitee_role text default 'member', valid_for interval default '7 days')
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_invitation"($1, $2, $3, $4) $$;
revoke execute on function "api"."create_invitation"(uuid, text, text, interval) from public, anon;
grant execute on function "api"."create_invitation"(uuid, text, text, interval) to authenticated, service_role;

create or replace function "api"."resend_invitation"(invitation_id uuid, valid_for interval default '7 days')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resend_invitation"($1, $2) $$;
revoke execute on function "api"."resend_invitation"(uuid, interval) from public, anon;
grant execute on function "api"."resend_invitation"(uuid, interval) to authenticated, service_role;

create or replace function "api"."update_invitation"(invitation_id uuid, invitee_email text default null, invitee_role text default null, prefill jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_invitation"($1, $2, $3, $4) $$;
revoke execute on function "api"."update_invitation"(uuid, text, text, jsonb) from public, anon;
grant execute on function "api"."update_invitation"(uuid, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."revoke_invitation"(invitation_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revoke_invitation"($1) $$;
revoke execute on function "api"."revoke_invitation"(uuid) from public, anon;
grant execute on function "api"."revoke_invitation"(uuid) to authenticated, service_role;

create or replace function "api"."decline_invitation"(token text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decline_invitation"($1) $$;
revoke execute on function "api"."decline_invitation"(text) from public;
grant execute on function "api"."decline_invitation"(text) to anon, authenticated, service_role;

create or replace function "api"."invitation_preview"(token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."invitation_preview"($1) $$;
revoke execute on function "api"."invitation_preview"(text) from public;
grant execute on function "api"."invitation_preview"(text) to anon, authenticated, service_role;

create or replace function "api"."accept_invitation"(token text)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."accept_invitation"($1) $$;
revoke execute on function "api"."accept_invitation"(text) from public, anon, service_role;
grant execute on function "api"."accept_invitation"(text) to authenticated;

create or replace function "api"."accept_invitation_by_id"(invitation_id uuid)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."accept_invitation_by_id"($1) $$;
revoke execute on function "api"."accept_invitation_by_id"(uuid) from public, anon, service_role;
grant execute on function "api"."accept_invitation_by_id"(uuid) to authenticated;

create or replace function "api"."decline_invitation_by_id"(invitation_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decline_invitation_by_id"($1) $$;
revoke execute on function "api"."decline_invitation_by_id"(uuid) from public, anon, service_role;
grant execute on function "api"."decline_invitation_by_id"(uuid) to authenticated;

create or replace function "api"."my_invitations"()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."my_invitations"() $$;
revoke execute on function "api"."my_invitations"() from public, anon, service_role;
grant execute on function "api"."my_invitations"() to authenticated;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_005_invitations.sql
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

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_005_invitations.sql
-- better-supabase module: invitations
-- @bsb-block invitations@2 managed
-- @bsb-hash sha256:55d13341c20ad6f99c13258292ee5b38ce967d4838f349f9bb6eb5b756f5916b
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."invitations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- better_supabase.invitations is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."invitations" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."invitations" add column if not exists "organization_id" uuid;
alter table "better_supabase"."invitations" add column if not exists "email" text;
alter table "better_supabase"."invitations" add column if not exists "role" text;
alter table "better_supabase"."invitations" add column if not exists "token_hash" text;
alter table "better_supabase"."invitations" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."invitations" add column if not exists "accepted_at" timestamptz;
alter table "better_supabase"."invitations" add column if not exists "invited_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."invitations" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."invitations" add column if not exists "accepted_by" uuid references auth.users (id) on delete set null;
alter table "better_supabase"."invitations" add column if not exists "declined_at" timestamptz;
alter table "better_supabase"."invitations" add column if not exists "revoked_at" timestamptz;
alter table "better_supabase"."invitations" add column if not exists "prefill" jsonb not null default '{}';

drop index if exists "better_supabase".invitations_open_idx;
create unique index if not exists invitations_open_email_idx
  on "better_supabase"."invitations" ("organization_id", lower("email")) where "accepted_at" is null and "declined_at" is null and "revoked_at" is null;
create index if not exists invitations_tenant_created_idx on "better_supabase"."invitations" ("organization_id", "created_at");
alter table "better_supabase"."invitations" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."invitations";
create trigger bsb_updated_at before update on "better_supabase"."invitations"
  for each row execute function better_supabase.set_updated_at('updated_at');
create index if not exists invitations_invited_by_idx on "better_supabase"."invitations" ("invited_by");
create index if not exists invitations_accepted_by_idx on "better_supabase"."invitations" ("accepted_by");


alter table "better_supabase"."invitations" enable row level security;
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
drop policy if exists bsb_invitations_read on "better_supabase"."invitations";
create policy bsb_invitations_read on "better_supabase"."invitations" for select to authenticated
  using ("organization_id" in (select "better_supabase"."invitation_tenant_ids"()));

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
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or false then
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
  where i."organization_id" = tenant
    and lower(i."email") = lower(btrim(invitee_email))
    and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null;
  insert into "better_supabase"."invitations" ("organization_id", "email", "role", "token_hash", "invited_by", "expires_at", "prefill")
  values (tenant, lower(btrim(invitee_email)), invitee_role, encode(extensions.digest(token, 'sha256'), 'hex'), auth.uid(), now() + valid_for, coalesce(prefill, '{}'))
  returning * into created;
  null;
  return (jsonb_build_object(
    'id', created."id",
    'tenant', created."organization_id",
    'email', created."email",
    'role', created."role",
    'expires_at', created."expires_at",
    'created_at', created."created_at",
    'invited_by', created."invited_by",
    'organization', jsonb_build_object('id', created."organization_id"),
    'prefill', created."prefill",
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
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false))
  returning * into updated;
  if updated."id" is null then
    raise exception 'No open invitation %', invitation_id using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  null;
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', jsonb_build_object('id', updated."organization_id"),
    'prefill', updated."prefill",
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
  tenant := current_invite."organization_id";
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  if better_supabase.tenant_disabled(tenant) or false then
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
    where i."organization_id" = tenant
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
    if prefill is not null then
      updated."prefill" := prefill;
    end if;
    update "better_supabase"."invitations" i
    set "email" = updated."email",
      "role" = updated."role",
      "prefill" = updated."prefill"
    where i."id" = invitation_id
    returning * into updated;
  null;
  return (jsonb_build_object(
    'id', updated."id",
    'tenant', updated."organization_id",
    'email', updated."email",
    'role', updated."role",
    'expires_at', updated."expires_at",
    'created_at', updated."created_at",
    'invited_by', updated."invited_by",
    'organization', jsonb_build_object('id', updated."organization_id"),
    'prefill', updated."prefill",
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
  update "better_supabase"."invitations" i set "revoked_at" = now() where i."id" = invitation_id and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.member_can(auth.uid(), i."organization_id", 'members.invite'), false)) and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
  returning i."organization_id"::text into tenant;
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
  returning i."id", i."organization_id"::text into declined_id, tenant;
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
  returning i."id", i."organization_id"::text into declined_id, tenant;
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
    'tenant', i."organization_id",
    'expires_at', i."expires_at",
    'organization', jsonb_build_object('id', i."organization_id"),
    'prefill', i."prefill"
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
  if better_supabase.tenant_disabled(invite."organization_id") or false then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
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
  if better_supabase.tenant_disabled(invite."organization_id") or false then
    raise exception 'The invitation is invalid or has expired' using errcode = 'P0002', hint = 'INVITATION_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."memberships" m where m."organization_id" = invite."organization_id" and m."user_id" = me) then
    raise exception 'You are already a member' using errcode = '23505', hint = 'INVITATION_ALREADY_MEMBER';
  end if;
    if invite."invited_by" is not null
      and better_supabase.can_user(invite."invited_by", 'organization', invite."organization_id", 'members.invite') is false then
      raise exception 'The person who invited you can no longer invite members' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
    if invite."invited_by" is not null
      and not better_supabase.can_assign_as(invite."invited_by", invite."organization_id", invite."role"::text) then
      raise exception 'The person who invited you can no longer assign that role' using errcode = '42501', hint = 'INVITATION_INVITER_REVOKED';
    end if;
  insert into "better_supabase"."memberships" ("organization_id", "user_id", "role")
  values (invite."organization_id", me, invite."role");
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
    'role', i."role",
    'expires_at', i."expires_at",
    'created_at', i."created_at",
    'invited_by', i."invited_by",
    'organization', jsonb_build_object('id', i."organization_id"),
    'prefill', i."prefill",
    'token', null
  ) || "better_supabase"."invitation_extra"(i."id")) - 'token' as invitation, i."id" as id, i."expires_at" as expires_at
    from "better_supabase"."invitations" i
    where lower(i."email") = invitee_email
      and i."expires_at" >= now() and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null
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

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
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
drop policy if exists bsb_tenant_scope on "better_supabase"."invitations";
create policy bsb_tenant_scope on "better_supabase"."invitations" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("organization_id" in (select "better_supabase"."invitation_tenant_ids"()))
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_005_invitations.sql
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
