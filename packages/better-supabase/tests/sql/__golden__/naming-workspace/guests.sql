-- ==== schema supabase/schemas/900_better_supabase_32_guests.sql
-- better-supabase module: guests
-- @bsb-block guests@1 managed
-- People outside the organization (clients, contractors) invited by email who read, comment on and upload to the records they are granted, and see the invoices and bookings of the party they act for. Never members, never through an authorization library.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Guests: people outside the organization (a client, a contractor) who reach
-- the records they are granted, and portal access for the party they act for.
-- A guest is never a member; policies add them through ctx.scope.guest.

create table if not exists "better_supabase"."guests" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "email" text not null check (length("email") >= 3 and length("email") <= 320 and position('@' in "email") > 1),
  "name" text check ("name" is null or length("name") between 1 and 200),
  "user_id" uuid references auth.users (id) on delete set null,
  "party_type" text,
  "party_id" text,
  "status" text not null default 'invited' check ("status" in ('invited', 'active', 'revoked')),
  "token_hash" text unique,
  "invited_by" uuid,
  "expires_at" timestamptz,
  "accepted_at" timestamptz,
  "revoked_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("party_type" is null) = ("party_id" is null)),
  check ("status" <> 'active' or "user_id" is not null)
);
create unique index if not exists "guests_email_idx" on "better_supabase"."guests" ("tenant_id", lower("email"));
create unique index if not exists "guests_user_idx" on "better_supabase"."guests" ("tenant_id", "user_id") where "user_id" is not null;
create index if not exists "guests_user_id_idx" on "better_supabase"."guests" ("user_id");
alter table "better_supabase"."guests" enable row level security;
revoke all on "better_supabase"."guests" from anon, authenticated;
grant select on "better_supabase"."guests" to authenticated;
grant all on "better_supabase"."guests" to service_role;
drop policy if exists "guests_read" on "better_supabase"."guests";
create policy "guests_read" on "better_supabase"."guests" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('guests.read')) or "user_id" = (select auth.uid()));

create table if not exists "better_supabase"."guest_grants" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "guest_id" uuid not null references "better_supabase"."guests" ("id") on delete cascade,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "actions" text[] not null check (cardinality("actions") > 0 and "actions" <@ array['read', 'comment', 'upload']::text[] and 'read' = any("actions")),
  "granted_by" uuid,
  "expires_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("guest_id", "subject_type", "subject_id")
);
create index if not exists "guest_grants_subject_idx" on "better_supabase"."guest_grants" ("tenant_id", "subject_type", "subject_id");
alter table "better_supabase"."guest_grants" enable row level security;
revoke all on "better_supabase"."guest_grants" from anon, authenticated;
grant select on "better_supabase"."guest_grants" to authenticated;
grant all on "better_supabase"."guest_grants" to service_role;
drop policy if exists "guest_grants_read" on "better_supabase"."guest_grants";
create policy "guest_grants_read" on "better_supabase"."guest_grants" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('guests.read'))
    or "guest_id" in (select x."id" from "better_supabase"."guests" x where x."user_id" = (select auth.uid())));

-- The records the caller reaches as a guest for action (read, comment or
-- upload). A guest is not a member: can() stays false for them, and policies
-- add this set through ctx.scope.guest.
create or replace function better_supabase.portal_subjects(action text)
returns table (tenant text, subject_type text, subject_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select x."tenant_id"::text, y."subject_type", y."subject_id"
  from "better_supabase"."guest_grants" y
  join "better_supabase"."guests" x on x."id" = y."guest_id"
  where x."status" = 'active' and x."user_id" = auth.uid() and not better_supabase.tenant_disabled(x."tenant_id") and not better_supabase.user_disabled(auth.uid())
    and portal_subjects.action = any(y."actions")
    and (y."expires_at" is null or y."expires_at" > now())
$$;
revoke execute on function better_supabase.portal_subjects(text) from public, anon;
grant execute on function better_supabase.portal_subjects(text) to authenticated, service_role;

-- The parties (a company, a person) the caller acts for as a guest, for
-- portal reads such as a customer's own invoices.
create or replace function better_supabase.portal_parties()
returns table (tenant text, party_type text, party_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select x."tenant_id"::text, x."party_type", x."party_id"
  from "better_supabase"."guests" x
  where x."status" = 'active' and x."user_id" = auth.uid() and not better_supabase.tenant_disabled(x."tenant_id") and not better_supabase.user_disabled(auth.uid()) and x."party_type" is not null
$$;
revoke execute on function better_supabase.portal_parties() from public, anon;
grant execute on function better_supabase.portal_parties() to authenticated, service_role;

-- Whether the caller reaches subject_type/subject_id as a guest for action.
create or replace function "better_supabase"."guest_can"(subject_type text, subject_id text, action text default 'read')
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from better_supabase.portal_subjects(guest_can.action) s
    where s.subject_type = guest_can.subject_type and s.subject_id = guest_can.subject_id
  )
$$;
revoke execute on function "better_supabase"."guest_can"(text, text, text) from public, anon;
grant execute on function "better_supabase"."guest_can"(text, text, text) to authenticated, service_role;

-- Invites email as a guest of tenant, acting for party_type/party_id (a
-- customer company or person) when set. Returns the guest with a one-time
-- token for the invite link. Inviting an email again issues a new token,
-- unless the guest has already accepted.
create or replace function "better_supabase"."invite_guest"(tenant uuid, email text, name text default null, party_type text default null, party_id text default null, expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."guests"%rowtype;
  v_token text;
  v_email text := lower(btrim(invite_guest.email));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', invite_guest.tenant, 'guests.manage'), false)) then
    raise exception 'not allowed to manage guests' using errcode = '42501', hint = 'GUEST_FORBIDDEN';
  end if;
  if (invite_guest.party_type is null) <> (invite_guest.party_id is null) then
    raise exception 'pass party_type and party_id together' using errcode = '22023', hint = 'GUEST_PARTY_INVALID';
  end if;
  if invite_guest.party_type is not null
    and null::text is distinct from invite_guest.tenant::text then
    raise exception 'the party does not exist in this organization' using errcode = 'P0002', hint = 'GUEST_PARTY_NOT_FOUND';
  end if;
  if invite_guest.expires_at is not null and invite_guest.expires_at <= now() then
    raise exception 'expires_at must be in the future' using errcode = '22023', hint = 'GUEST_EXPIRES_IN_PAST';
  end if;
  select * into v_row from "better_supabase"."guests" x
    where x."tenant_id" = invite_guest.tenant and lower(x."email") = v_email
    for update;
  if found and v_row."status" = 'active' then
    update "better_supabase"."guests" x set
      "name" = coalesce(invite_guest.name, x."name"),
      "party_type" = coalesce(invite_guest.party_type, x."party_type"),
      "party_id" = coalesce(invite_guest.party_id, x."party_id"),
      "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'email', v_row."email", 'name', v_row."name", 'userId', v_row."user_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'invitedBy', v_row."invited_by", 'expiresAt', v_row."expires_at", 'acceptedAt', v_row."accepted_at", 'revokedAt', v_row."revoked_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('token', null);
  end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  if found then
    update "better_supabase"."guests" x set
      "name" = coalesce(invite_guest.name, x."name"),
      "party_type" = coalesce(invite_guest.party_type, x."party_type"),
      "party_id" = coalesce(invite_guest.party_id, x."party_id"),
      "status" = 'invited',
      "user_id" = null,
      "token_hash" = encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'),
      "invited_by" = auth.uid(),
      "expires_at" = invite_guest.expires_at,
      "revoked_at" = null,
      "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
  else
    insert into "better_supabase"."guests" ("tenant_id", "email", "name", "party_type", "party_id", "token_hash", "invited_by", "expires_at")
    values (invite_guest.tenant, v_email, invite_guest.name, invite_guest.party_type, invite_guest.party_id, encode(extensions.digest(convert_to(v_token, 'utf8'), 'sha256'), 'hex'), auth.uid(), invite_guest.expires_at)
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'email', v_row."email", 'name', v_row."name", 'userId', v_row."user_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'invitedBy', v_row."invited_by", 'expiresAt', v_row."expires_at", 'acceptedAt', v_row."accepted_at", 'revokedAt', v_row."revoked_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('token', v_token);
end;
$$;
revoke execute on function "better_supabase"."invite_guest"(uuid, text, text, text, text, timestamptz) from public, anon;
grant execute on function "better_supabase"."invite_guest"(uuid, text, text, text, text, timestamptz) to authenticated, service_role;

-- The signed-in invitee accepts with the token. Their confirmed email must
-- match the invite, so a forwarded link doesn't let someone else in.
create or replace function "better_supabase"."accept_guest_invite"(token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."guests"%rowtype;
  v_email text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in to accept the invite' using errcode = '42501', hint = 'GUEST_SIGN_IN_REQUIRED';
  end if;
  select * into v_row from "better_supabase"."guests" x
    where x."token_hash" = encode(extensions.digest(convert_to(accept_guest_invite.token, 'utf8'), 'sha256'), 'hex')
      and x."status" = 'invited'
      and (x."expires_at" is null or x."expires_at" > now())
    for update;
  if not found then
    raise exception 'this invite is not valid or has expired' using errcode = 'P0002', hint = 'GUEST_INVITE_INVALID';
  end if;
  select lower(u.email) into v_email from auth.users u
    where u.id = auth.uid() and u.email_confirmed_at is not null;
  if v_email is distinct from lower(v_row."email") then
    raise exception 'this invite was sent to another email' using errcode = '42501', hint = 'GUEST_EMAIL_MISMATCH';
  end if;
  if exists (
    select 1 from "better_supabase"."guests" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = auth.uid() and x."id" <> v_row."id"
  ) then
    raise exception 'you are already a guest of this organization' using errcode = '23505', hint = 'GUEST_ALREADY_GUEST';
  end if;
  update "better_supabase"."guests" x set
    "user_id" = auth.uid(),
    "status" = 'active',
    "token_hash" = null,
    "accepted_at" = now(),
    "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'email', v_row."email", 'name', v_row."name", 'userId', v_row."user_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'invitedBy', v_row."invited_by", 'expiresAt', v_row."expires_at", 'acceptedAt', v_row."accepted_at", 'revokedAt', v_row."revoked_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."accept_guest_invite"(text) from public, anon;
grant execute on function "better_supabase"."accept_guest_invite"(text) to authenticated, service_role;

-- Revokes a guest: their grants stop counting and the invite token is
-- dropped. Inviting the email again restores them.
create or replace function "better_supabase"."revoke_guest"(guest_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."guests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."guests" x where x."id" = revoke_guest.guest_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'guests.manage'), false)) then
    raise exception 'guest not found' using errcode = 'P0002', hint = 'GUEST_NOT_FOUND';
  end if;
  if v_row."status" <> 'revoked' then
    update "better_supabase"."guests" x set
      "status" = 'revoked',
      "token_hash" = null,
      "revoked_at" = now(),
      "updated_at" = now()
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'email', v_row."email", 'name', v_row."name", 'userId', v_row."user_id", 'partyType', v_row."party_type", 'partyId', v_row."party_id", 'status', v_row."status", 'invitedBy', v_row."invited_by", 'expiresAt', v_row."expires_at", 'acceptedAt', v_row."accepted_at", 'revokedAt', v_row."revoked_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."revoke_guest"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_guest"(uuid) to authenticated, service_role;

-- Lets a guest reach one record: read always, and comment or upload when
-- actions names them. Granting the same record again replaces the actions
-- and the expiry.
create or replace function "better_supabase"."grant_guest_access"(guest_id uuid, subject_type text, subject_id text, actions text[] default array['read'], expires_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_guest "better_supabase"."guests"%rowtype;
  v_row "better_supabase"."guest_grants"%rowtype;
  v_actions text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_guest from "better_supabase"."guests" x where x."id" = grant_guest_access.guest_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_guest."tenant_id", 'guests.manage'), false)) then
    raise exception 'guest not found' using errcode = 'P0002', hint = 'GUEST_NOT_FOUND';
  end if;
  if v_guest."status" = 'revoked' then
    raise exception 'invite the guest again before granting access' using errcode = '55000', hint = 'GUEST_REVOKED';
  end if;
  if not (coalesce(grant_guest_access.actions, '{}') <@ array['read', 'comment', 'upload']::text[]) then
    raise exception 'actions are read, comment and upload' using errcode = '22023', hint = 'GUEST_ACTION_INVALID';
  end if;
  select array_agg(a order by array_position(array['read', 'comment', 'upload']::text[], a)) into v_actions
    from (select distinct a from unnest(array_append(coalesce(grant_guest_access.actions, '{}'), 'read')) a) z;
  if grant_guest_access.expires_at is not null and grant_guest_access.expires_at <= now() then
    raise exception 'expires_at must be in the future' using errcode = '22023', hint = 'GUEST_EXPIRES_IN_PAST';
  end if;
  if null::text is distinct from v_guest."tenant_id"::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'GUEST_SUBJECT_NOT_FOUND';
  end if;
  insert into "better_supabase"."guest_grants" as y ("tenant_id", "guest_id", "subject_type", "subject_id", "actions", "granted_by", "expires_at")
  values (v_guest."tenant_id", v_guest."id", grant_guest_access.subject_type, grant_guest_access.subject_id, v_actions, auth.uid(), grant_guest_access.expires_at)
  on conflict ("guest_id", "subject_type", "subject_id") do update set
    "actions" = excluded."actions",
    "granted_by" = excluded."granted_by",
    "expires_at" = excluded."expires_at",
    "updated_at" = now()
  returning * into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'guestId', v_row."guest_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'actions', to_jsonb(v_row."actions"), 'grantedBy', v_row."granted_by", 'expiresAt', v_row."expires_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."grant_guest_access"(uuid, text, text, text[], timestamptz) from public, anon;
grant execute on function "better_supabase"."grant_guest_access"(uuid, text, text, text[], timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."revoke_guest_access"(grant_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."guest_grants"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."guest_grants" y where y."id" = revoke_guest_access.grant_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'guests.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."guest_grants" y where y."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."revoke_guest_access"(uuid) from public, anon;
grant execute on function "better_supabase"."revoke_guest_access"(uuid) to authenticated, service_role;

-- A tenant's guests, newest first. status filters; before pages back from a
-- guest's created_at.
create or replace function "better_supabase"."list_guests"(tenant uuid, status text default null, before timestamptz default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_guests.tenant, 'guests.read'), false)) then
    raise exception 'not allowed to read guests' using errcode = '42501', hint = 'GUEST_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(z.item order by z.created desc, z.id desc), '[]'::jsonb)
    from (
      select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'email', x."email", 'name', x."name", 'userId', x."user_id", 'partyType', x."party_type", 'partyId', x."party_id", 'status', x."status", 'invitedBy', x."invited_by", 'expiresAt', x."expires_at", 'acceptedAt', x."accepted_at", 'revokedAt', x."revoked_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as item, x."created_at" as created, x."id" as id
      from "better_supabase"."guests" x
      where x."tenant_id" = list_guests.tenant
        and (list_guests.status is null or x."status" = list_guests.status)
        and (list_guests.before is null or x."created_at" < list_guests.before)
      order by x."created_at" desc, x."id" desc
      limit least(greatest(coalesce(list_guests.page_size, 50), 1), 500)
    ) z
  );
end;
$$;
revoke execute on function "better_supabase"."list_guests"(uuid, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."list_guests"(uuid, text, timestamptz, integer) to authenticated, service_role;

-- The guests who reach one record, with their grant, for the record's
-- sharing panel.
create or replace function "better_supabase"."list_guest_grants"(subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant text := null::text;
begin
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant::uuid, 'guests.read'), false)) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id"::text, 'guestId', y."guest_id", 'subjectType', y."subject_type", 'subjectId', y."subject_id", 'actions', to_jsonb(y."actions"), 'grantedBy', y."granted_by", 'expiresAt', y."expires_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") || jsonb_build_object('guest', jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'email', x."email", 'name', x."name", 'userId', x."user_id", 'partyType', x."party_type", 'partyId', x."party_id", 'status', x."status", 'invitedBy', x."invited_by", 'expiresAt', x."expires_at", 'acceptedAt', x."accepted_at", 'revokedAt', x."revoked_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at")) order by y."created_at", y."id"), '[]'::jsonb)
    from "better_supabase"."guest_grants" y
    join "better_supabase"."guests" x on x."id" = y."guest_id"
    where y."tenant_id"::text = v_tenant
      and y."subject_type" = list_guest_grants.subject_type
      and y."subject_id" = list_guest_grants.subject_id
  );
end;
$$;
revoke execute on function "better_supabase"."list_guest_grants"(text, text) from public, anon;
grant execute on function "better_supabase"."list_guest_grants"(text, text) to authenticated, service_role;

-- What the caller reaches as a guest, per organization, for a portal's home
-- page: the party they act for and their live grants.
create or replace function "better_supabase"."my_guest_access"()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id"::text, 'email', x."email", 'name', x."name", 'userId', x."user_id", 'partyType', x."party_type", 'partyId', x."party_id", 'status', x."status", 'invitedBy', x."invited_by", 'expiresAt', x."expires_at", 'acceptedAt', x."accepted_at", 'revokedAt', x."revoked_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('grants', (
    select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id"::text, 'guestId', y."guest_id", 'subjectType', y."subject_type", 'subjectId', y."subject_id", 'actions', to_jsonb(y."actions"), 'grantedBy', y."granted_by", 'expiresAt', y."expires_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."created_at", y."id"), '[]'::jsonb)
    from "better_supabase"."guest_grants" y
    where y."guest_id" = x."id" and (y."expires_at" is null or y."expires_at" > now())
  )) order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."guests" x
  where x."status" = 'active' and x."user_id" = auth.uid() and not better_supabase.tenant_disabled(x."tenant_id") and not better_supabase.user_disabled(auth.uid())
$$;
revoke execute on function "better_supabase"."my_guest_access"() from public, anon;
grant execute on function "better_supabase"."my_guest_access"() to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."guests";
create policy bsb_tenant_scope on "better_supabase"."guests" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('guests.read')) or "user_id" = (select auth.uid()))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."guest_grants";
create policy bsb_tenant_scope on "better_supabase"."guest_grants" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('guests.read'))
    or "guest_id" in (select x."id" from "better_supabase"."guests" x where x."user_id" = (select auth.uid())))
  )
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_32_guests.sql
-- better-supabase module: guests
-- @bsb-block-data guests
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('guests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
