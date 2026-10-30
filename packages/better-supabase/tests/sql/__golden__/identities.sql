-- ==== alone: schema supabase/schemas/900_better_supabase_089_identities.sql
-- better-supabase module: identities
-- @bsb-block identities@1 managed
-- @bsb-hash sha256:8caa8c3bdddefd3f2d65ae734a26adabf259b487e20ea476f0b165f9f7b93360
-- Links an email address or a chat user to an app user or a contact. Rows come only from a one-time code the signed-in user issues and the service redeems, or from a confirmed address in auth.users.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Maps an email address or a chat user to an app user or a contact. Rows
-- come from a link code the signed-in user issued and the service redeemed
-- (redeem_identity_link), or from a confirmed address in auth.users
-- (link_verified_email). Users read and delete their own; nobody inserts or
-- updates directly.
create table if not exists "better_supabase"."identity_links" (
  "id" uuid primary key default gen_random_uuid(),
  "kind" text not null check ("kind" in ('email', 'chat')),
  "provider" text check (length("provider") between 1 and 100),
  "value" text not null check (length("value") between 1 and 500),
  "workspace" text check (length("workspace") between 1 and 200),
  "user_id" uuid references auth.users (id) on delete cascade,
  "contact_id" uuid,
  "source" text not null check ("source" in ('link', 'verified_email')),
  "created_at" timestamptz not null default now(),
  constraint identity_links_one_target check (num_nonnulls("user_id", "contact_id") = 1),
  constraint identity_links_email_lower check ("kind" <> 'email' or "value" = lower("value")),
  constraint identity_links_identity_key unique nulls not distinct ("kind", "provider", "value", "workspace")
);
create index if not exists identity_links_user_idx on "better_supabase"."identity_links" ("user_id");
create index if not exists identity_links_contact_idx on "better_supabase"."identity_links" ("contact_id");
alter table "better_supabase"."identity_links" enable row level security;
revoke all on "better_supabase"."identity_links" from public, anon, authenticated;
grant select, delete on "better_supabase"."identity_links" to authenticated;
grant all on "better_supabase"."identity_links" to service_role;
drop policy if exists identity_links_own_read on "better_supabase"."identity_links";
create policy identity_links_own_read on "better_supabase"."identity_links"
  for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists identity_links_own_delete on "better_supabase"."identity_links";
create policy identity_links_own_delete on "better_supabase"."identity_links"
  for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

-- One-time link codes, stored as SHA-256. No policy: only the functions below read them.
create table if not exists "better_supabase"."identity_link_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "kind" text not null check ("kind" in ('email', 'chat')),
  "provider" text check (length("provider") between 1 and 100),
  "code_hash" text not null unique,
  "expires_at" timestamptz not null,
  "used_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists identity_link_codes_user_idx on "better_supabase"."identity_link_codes" ("user_id");
alter table "better_supabase"."identity_link_codes" enable row level security;
revoke all on "better_supabase"."identity_link_codes" from public, anon, authenticated;
grant all on "better_supabase"."identity_link_codes" to service_role;

-- Issues a one-time code for the caller to hand to the bot or the mail
-- side. Issuing replaces the caller's unused codes for the same kind and
-- provider. Returns the code once.
create or replace function "better_supabase"."begin_identity_link"(kind text, provider text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_code text := upper(encode(extensions.gen_random_bytes(6), 'hex'));
  v_expires timestamptz := now() + interval '10 minutes';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to link an identity' using errcode = '42501', hint = 'IDENTITY_SIGN_IN_REQUIRED';
  end if;
  if begin_identity_link.kind is null or begin_identity_link.kind not in ('email', 'chat') then
    raise exception 'kind must be email or chat' using errcode = '22023', hint = 'IDENTITY_KIND';
  end if;
  delete from "better_supabase"."identity_link_codes"
  where "user_id" = v_user and "kind" = begin_identity_link.kind
    and "provider" is not distinct from begin_identity_link.provider
    and "used_at" is null;
  insert into "better_supabase"."identity_link_codes" ("user_id", "kind", "provider", "code_hash", "expires_at")
  values (v_user, begin_identity_link.kind, begin_identity_link.provider, encode(extensions.digest(convert_to(v_code, 'utf8'), 'sha256'), 'hex'), v_expires);
  return jsonb_build_object('code', v_code, 'expires_at', v_expires);
end;
$$;
revoke execute on function "better_supabase"."begin_identity_link"(text, text) from public, anon;
grant execute on function "better_supabase"."begin_identity_link"(text, text) to authenticated, service_role;

-- Binds the identity the bot or mail side saw to the user who issued the
-- code. A used, expired or unknown code, or an identity someone else holds,
-- is refused. Service role only: the caller vouches for the identity.
create or replace function "better_supabase"."redeem_identity_link"(code text, kind text, provider text, value text, workspace text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code_id uuid;
  v_user uuid;
  v_value text := case when redeem_identity_link.kind = 'email' then lower(trim(redeem_identity_link.value)) else redeem_identity_link.value end;
  v_link "better_supabase"."identity_links";
begin
  if redeem_identity_link.code is null or v_value is null or length(v_value) = 0 then
    raise exception 'invalid or expired link code' using errcode = '22023', hint = 'IDENTITY_LINK_INVALID';
  end if;
  select "id", "user_id" into v_code_id, v_user
  from "better_supabase"."identity_link_codes"
  where "code_hash" = encode(extensions.digest(convert_to(upper(regexp_replace(redeem_identity_link.code, '[^0-9A-Za-z]', '', 'g')), 'utf8'), 'sha256'), 'hex')
    and "kind" = redeem_identity_link.kind
    and "provider" is not distinct from redeem_identity_link.provider
    and "used_at" is null
    and "expires_at" > now()
  for update;
  if not found then
    raise exception 'invalid or expired link code' using errcode = '22023', hint = 'IDENTITY_LINK_INVALID';
  end if;
  update "better_supabase"."identity_link_codes" set "used_at" = now() where "id" = v_code_id;
  select * into v_link from "better_supabase"."identity_links"
  where "kind" = redeem_identity_link.kind
    and "provider" is not distinct from redeem_identity_link.provider
    and "value" = v_value
    and "workspace" is not distinct from redeem_identity_link.workspace;
  if found then
    if v_link."user_id" is distinct from v_user then
      raise exception 'this identity is linked to someone else' using errcode = '23505', hint = 'IDENTITY_TAKEN';
    end if;
  else
    insert into "better_supabase"."identity_links" ("kind", "provider", "value", "workspace", "user_id", "source")
    values (redeem_identity_link.kind, redeem_identity_link.provider, v_value, redeem_identity_link.workspace, v_user, 'link')
    returning * into v_link;
  end if;
  return jsonb_build_object('id', v_link."id", 'user_id', v_user);
end;
$$;
revoke execute on function "better_supabase"."redeem_identity_link"(text, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."redeem_identity_link"(text, text, text, text, text) to service_role;

-- The link for an identity: {kind: 'user', userId} or {kind: 'contact',
-- contactId}, or null. An email address also matches a row stored without
-- a provider or workspace, such as a verified address.
create or replace function "better_supabase"."principal_by_identity"(kind text, provider text, value text, workspace text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when "user_id" is not null
    then jsonb_build_object('kind', 'user', 'userId', "user_id")
    else jsonb_build_object('kind', 'contact', 'contactId', "contact_id")
  end
  from "better_supabase"."identity_links"
  where "kind" = principal_by_identity.kind
    and "value" = case when principal_by_identity.kind = 'email' then lower(trim(principal_by_identity.value)) else principal_by_identity.value end
    and ("provider" is not distinct from principal_by_identity.provider or ("kind" = 'email' and "provider" is null))
    and ("workspace" is not distinct from principal_by_identity.workspace or ("kind" = 'email' and "workspace" is null))
  order by "provider" is null, "workspace" is null
  limit 1
$$;
revoke execute on function "better_supabase"."principal_by_identity"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."principal_by_identity"(text, text, text, text) to service_role;

-- Creates the email identity for a user whose address is confirmed. Does
-- nothing for an unconfirmed address or one that is already linked.
create or replace function "better_supabase"."link_verified_email"(user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_email text;
begin
  select lower(trim(u.email)) into v_email
  from auth.users u
  where u.id = link_verified_email.user_id and u.email_confirmed_at is not null and u.email is not null and length(trim(u.email)) > 0;
  if v_email is null then
    return false;
  end if;
  insert into "better_supabase"."identity_links" ("kind", "value", "user_id", "source")
  values ('email', v_email, link_verified_email.user_id, 'verified_email')
  on conflict ("kind", "provider", "value", "workspace") do nothing;
  return found;
end;
$$;
revoke execute on function "better_supabase"."link_verified_email"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."link_verified_email"(uuid) to service_role;

-- Creates the email identities for users confirmed before the module was installed.
create or replace function "better_supabase"."backfill_verified_emails"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from auth.users u
  where u.email_confirmed_at is not null and "better_supabase"."link_verified_email"(u.id)
$$;
revoke execute on function "better_supabase"."backfill_verified_emails"() from public, anon, authenticated;
grant execute on function "better_supabase"."backfill_verified_emails"() to service_role;

-- The caller's identities, through the read policy.
create or replace function "better_supabase"."my_identities"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', "id", 'kind', "kind", 'provider', "provider", 'value', "value",
    'workspace', "workspace", 'source', "source", 'created_at', "created_at"
  ) order by "created_at"), '[]'::jsonb)
  from "better_supabase"."identity_links"
  where "user_id" = (select auth.uid())
$$;
revoke execute on function "better_supabase"."my_identities"() from public, anon;
grant execute on function "better_supabase"."my_identities"() to authenticated, service_role;

-- Removes one of the caller's identities, through the delete policy.
create or replace function "better_supabase"."unlink_identity"(id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from "better_supabase"."identity_links" where "id" = unlink_identity.id and "user_id" = (select auth.uid());
  return found;
end;
$$;
revoke execute on function "better_supabase"."unlink_identity"(uuid) from public, anon;
grant execute on function "better_supabase"."unlink_identity"(uuid) to authenticated, service_role;

-- Keeps the email identity of each user equal to the confirmed address in
-- auth.users. An address another user or contact holds stays theirs.
create or replace function "better_supabase"."on_auth_user_email"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    if tg_op = 'UPDATE' and old.email is distinct from new.email then
      delete from "better_supabase"."identity_links"
      where "user_id" = new.id and "kind" = 'email' and "source" = 'verified_email';
    end if;
    perform "better_supabase"."link_verified_email"(new.id);
  exception when others then
    raise warning 'No email identity for user %: % (SQLSTATE %)', new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
revoke execute on function "better_supabase"."on_auth_user_email"() from public, anon, authenticated;
drop trigger if exists "bsb_identity_email" on auth.users;
create trigger "bsb_identity_email" after insert or update of email, email_confirmed_at on auth.users
  for each row execute function "better_supabase"."on_auth_user_email"();

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_089_identities.sql
-- better-supabase module: identities
-- @bsb-block-data identities
-- @bsb-hash sha256:cd6777a400827759d290e0dde0a7d52f5d50f12b8537a48f4be35b8b3a40cf69
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('identities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_089_identities.sql
-- better-supabase module: identities
-- @bsb-block identities@1 managed
-- @bsb-hash sha256:8caa8c3bdddefd3f2d65ae734a26adabf259b487e20ea476f0b165f9f7b93360
-- Links an email address or a chat user to an app user or a contact. Rows come only from a one-time code the signed-in user issues and the service redeems, or from a confirmed address in auth.users.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Maps an email address or a chat user to an app user or a contact. Rows
-- come from a link code the signed-in user issued and the service redeemed
-- (redeem_identity_link), or from a confirmed address in auth.users
-- (link_verified_email). Users read and delete their own; nobody inserts or
-- updates directly.
create table if not exists "better_supabase"."identity_links" (
  "id" uuid primary key default gen_random_uuid(),
  "kind" text not null check ("kind" in ('email', 'chat')),
  "provider" text check (length("provider") between 1 and 100),
  "value" text not null check (length("value") between 1 and 500),
  "workspace" text check (length("workspace") between 1 and 200),
  "user_id" uuid references auth.users (id) on delete cascade,
  "contact_id" uuid,
  "source" text not null check ("source" in ('link', 'verified_email')),
  "created_at" timestamptz not null default now(),
  constraint identity_links_one_target check (num_nonnulls("user_id", "contact_id") = 1),
  constraint identity_links_email_lower check ("kind" <> 'email' or "value" = lower("value")),
  constraint identity_links_identity_key unique nulls not distinct ("kind", "provider", "value", "workspace")
);
create index if not exists identity_links_user_idx on "better_supabase"."identity_links" ("user_id");
create index if not exists identity_links_contact_idx on "better_supabase"."identity_links" ("contact_id");
alter table "better_supabase"."identity_links" enable row level security;
revoke all on "better_supabase"."identity_links" from public, anon, authenticated;
grant select, delete on "better_supabase"."identity_links" to authenticated;
grant all on "better_supabase"."identity_links" to service_role;
drop policy if exists identity_links_own_read on "better_supabase"."identity_links";
create policy identity_links_own_read on "better_supabase"."identity_links"
  for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists identity_links_own_delete on "better_supabase"."identity_links";
create policy identity_links_own_delete on "better_supabase"."identity_links"
  for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

-- One-time link codes, stored as SHA-256. No policy: only the functions below read them.
create table if not exists "better_supabase"."identity_link_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "kind" text not null check ("kind" in ('email', 'chat')),
  "provider" text check (length("provider") between 1 and 100),
  "code_hash" text not null unique,
  "expires_at" timestamptz not null,
  "used_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists identity_link_codes_user_idx on "better_supabase"."identity_link_codes" ("user_id");
alter table "better_supabase"."identity_link_codes" enable row level security;
revoke all on "better_supabase"."identity_link_codes" from public, anon, authenticated;
grant all on "better_supabase"."identity_link_codes" to service_role;

-- Issues a one-time code for the caller to hand to the bot or the mail
-- side. Issuing replaces the caller's unused codes for the same kind and
-- provider. Returns the code once.
create or replace function "better_supabase"."begin_identity_link"(kind text, provider text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_code text := upper(encode(extensions.gen_random_bytes(6), 'hex'));
  v_expires timestamptz := now() + interval '10 minutes';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to link an identity' using errcode = '42501', hint = 'IDENTITY_SIGN_IN_REQUIRED';
  end if;
  if begin_identity_link.kind is null or begin_identity_link.kind not in ('email', 'chat') then
    raise exception 'kind must be email or chat' using errcode = '22023', hint = 'IDENTITY_KIND';
  end if;
  delete from "better_supabase"."identity_link_codes"
  where "user_id" = v_user and "kind" = begin_identity_link.kind
    and "provider" is not distinct from begin_identity_link.provider
    and "used_at" is null;
  insert into "better_supabase"."identity_link_codes" ("user_id", "kind", "provider", "code_hash", "expires_at")
  values (v_user, begin_identity_link.kind, begin_identity_link.provider, encode(extensions.digest(convert_to(v_code, 'utf8'), 'sha256'), 'hex'), v_expires);
  return jsonb_build_object('code', v_code, 'expires_at', v_expires);
end;
$$;
revoke execute on function "better_supabase"."begin_identity_link"(text, text) from public, anon;
grant execute on function "better_supabase"."begin_identity_link"(text, text) to authenticated, service_role;

-- Binds the identity the bot or mail side saw to the user who issued the
-- code. A used, expired or unknown code, or an identity someone else holds,
-- is refused. Service role only: the caller vouches for the identity.
create or replace function "better_supabase"."redeem_identity_link"(code text, kind text, provider text, value text, workspace text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code_id uuid;
  v_user uuid;
  v_value text := case when redeem_identity_link.kind = 'email' then lower(trim(redeem_identity_link.value)) else redeem_identity_link.value end;
  v_link "better_supabase"."identity_links";
begin
  if redeem_identity_link.code is null or v_value is null or length(v_value) = 0 then
    raise exception 'invalid or expired link code' using errcode = '22023', hint = 'IDENTITY_LINK_INVALID';
  end if;
  select "id", "user_id" into v_code_id, v_user
  from "better_supabase"."identity_link_codes"
  where "code_hash" = encode(extensions.digest(convert_to(upper(regexp_replace(redeem_identity_link.code, '[^0-9A-Za-z]', '', 'g')), 'utf8'), 'sha256'), 'hex')
    and "kind" = redeem_identity_link.kind
    and "provider" is not distinct from redeem_identity_link.provider
    and "used_at" is null
    and "expires_at" > now()
  for update;
  if not found then
    raise exception 'invalid or expired link code' using errcode = '22023', hint = 'IDENTITY_LINK_INVALID';
  end if;
  update "better_supabase"."identity_link_codes" set "used_at" = now() where "id" = v_code_id;
  select * into v_link from "better_supabase"."identity_links"
  where "kind" = redeem_identity_link.kind
    and "provider" is not distinct from redeem_identity_link.provider
    and "value" = v_value
    and "workspace" is not distinct from redeem_identity_link.workspace;
  if found then
    if v_link."user_id" is distinct from v_user then
      raise exception 'this identity is linked to someone else' using errcode = '23505', hint = 'IDENTITY_TAKEN';
    end if;
  else
    insert into "better_supabase"."identity_links" ("kind", "provider", "value", "workspace", "user_id", "source")
    values (redeem_identity_link.kind, redeem_identity_link.provider, v_value, redeem_identity_link.workspace, v_user, 'link')
    returning * into v_link;
  end if;
  return jsonb_build_object('id', v_link."id", 'user_id', v_user);
end;
$$;
revoke execute on function "better_supabase"."redeem_identity_link"(text, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."redeem_identity_link"(text, text, text, text, text) to service_role;

-- The link for an identity: {kind: 'user', userId} or {kind: 'contact',
-- contactId}, or null. An email address also matches a row stored without
-- a provider or workspace, such as a verified address.
create or replace function "better_supabase"."principal_by_identity"(kind text, provider text, value text, workspace text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when "user_id" is not null
    then jsonb_build_object('kind', 'user', 'userId', "user_id")
    else jsonb_build_object('kind', 'contact', 'contactId', "contact_id")
  end
  from "better_supabase"."identity_links"
  where "kind" = principal_by_identity.kind
    and "value" = case when principal_by_identity.kind = 'email' then lower(trim(principal_by_identity.value)) else principal_by_identity.value end
    and ("provider" is not distinct from principal_by_identity.provider or ("kind" = 'email' and "provider" is null))
    and ("workspace" is not distinct from principal_by_identity.workspace or ("kind" = 'email' and "workspace" is null))
  order by "provider" is null, "workspace" is null
  limit 1
$$;
revoke execute on function "better_supabase"."principal_by_identity"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."principal_by_identity"(text, text, text, text) to service_role;

-- Creates the email identity for a user whose address is confirmed. Does
-- nothing for an unconfirmed address or one that is already linked.
create or replace function "better_supabase"."link_verified_email"(user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_email text;
begin
  select lower(trim(u.email)) into v_email
  from auth.users u
  where u.id = link_verified_email.user_id and u.email_confirmed_at is not null and u.email is not null and length(trim(u.email)) > 0;
  if v_email is null then
    return false;
  end if;
  insert into "better_supabase"."identity_links" ("kind", "value", "user_id", "source")
  values ('email', v_email, link_verified_email.user_id, 'verified_email')
  on conflict ("kind", "provider", "value", "workspace") do nothing;
  return found;
end;
$$;
revoke execute on function "better_supabase"."link_verified_email"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."link_verified_email"(uuid) to service_role;

-- Creates the email identities for users confirmed before the module was installed.
create or replace function "better_supabase"."backfill_verified_emails"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from auth.users u
  where u.email_confirmed_at is not null and "better_supabase"."link_verified_email"(u.id)
$$;
revoke execute on function "better_supabase"."backfill_verified_emails"() from public, anon, authenticated;
grant execute on function "better_supabase"."backfill_verified_emails"() to service_role;

-- The caller's identities, through the read policy.
create or replace function "better_supabase"."my_identities"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', "id", 'kind', "kind", 'provider', "provider", 'value', "value",
    'workspace', "workspace", 'source', "source", 'created_at', "created_at"
  ) order by "created_at"), '[]'::jsonb)
  from "better_supabase"."identity_links"
  where "user_id" = (select auth.uid())
$$;
revoke execute on function "better_supabase"."my_identities"() from public, anon;
grant execute on function "better_supabase"."my_identities"() to authenticated, service_role;

-- Removes one of the caller's identities, through the delete policy.
create or replace function "better_supabase"."unlink_identity"(id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from "better_supabase"."identity_links" where "id" = unlink_identity.id and "user_id" = (select auth.uid());
  return found;
end;
$$;
revoke execute on function "better_supabase"."unlink_identity"(uuid) from public, anon;
grant execute on function "better_supabase"."unlink_identity"(uuid) to authenticated, service_role;

-- Keeps the email identity of each user equal to the confirmed address in
-- auth.users. An address another user or contact holds stays theirs.
create or replace function "better_supabase"."on_auth_user_email"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    if tg_op = 'UPDATE' and old.email is distinct from new.email then
      delete from "better_supabase"."identity_links"
      where "user_id" = new.id and "kind" = 'email' and "source" = 'verified_email';
    end if;
    perform "better_supabase"."link_verified_email"(new.id);
  exception when others then
    raise warning 'No email identity for user %: % (SQLSTATE %)', new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
revoke execute on function "better_supabase"."on_auth_user_email"() from public, anon, authenticated;
drop trigger if exists "bsb_identity_email" on auth.users;
create trigger "bsb_identity_email" after insert or update of email, email_confirmed_at on auth.users
  for each row execute function "better_supabase"."on_auth_user_email"();

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_089_identities.sql
-- better-supabase module: identities
-- @bsb-block-data identities
-- @bsb-hash sha256:cd6777a400827759d290e0dde0a7d52f5d50f12b8537a48f4be35b8b3a40cf69
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('identities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_089_identities.sql
-- better-supabase module: identities
-- @bsb-block identities@1 managed
-- @bsb-hash sha256:a9faeaac5e9445d74600d3de4ca0afc1ea53a9d147ec61969954b3884bae10db
-- Links an email address or a chat user to an app user or a contact. Rows come only from a one-time code the signed-in user issues and the service redeems, or from a confirmed address in auth.users.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Maps an email address or a chat user to an app user or a contact. Rows
-- come from a link code the signed-in user issued and the service redeemed
-- (redeem_identity_link), or from a confirmed address in auth.users
-- (link_verified_email). Users read and delete their own; nobody inserts or
-- updates directly.
create table if not exists "app_private"."identity_links" (
  "id" uuid primary key default gen_random_uuid(),
  "kind" text not null check ("kind" in ('email', 'chat')),
  "provider" text check (length("provider") between 1 and 100),
  "value" text not null check (length("value") between 1 and 500),
  "workspace" text check (length("workspace") between 1 and 200),
  "user_id" uuid references auth.users (id) on delete cascade,
  "contact_id" uuid,
  "source" text not null check ("source" in ('link', 'verified_email')),
  "created_at" timestamptz not null default now(),
  constraint identity_links_one_target check (num_nonnulls("user_id", "contact_id") = 1),
  constraint identity_links_email_lower check ("kind" <> 'email' or "value" = lower("value")),
  constraint identity_links_identity_key unique nulls not distinct ("kind", "provider", "value", "workspace")
);
create index if not exists identity_links_user_idx on "app_private"."identity_links" ("user_id");
create index if not exists identity_links_contact_idx on "app_private"."identity_links" ("contact_id");
alter table "app_private"."identity_links" enable row level security;
revoke all on "app_private"."identity_links" from public, anon, authenticated;
grant select, delete on "app_private"."identity_links" to authenticated;
grant all on "app_private"."identity_links" to service_role;
drop policy if exists identity_links_own_read on "app_private"."identity_links";
create policy identity_links_own_read on "app_private"."identity_links"
  for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists identity_links_own_delete on "app_private"."identity_links";
create policy identity_links_own_delete on "app_private"."identity_links"
  for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

-- One-time link codes, stored as SHA-256. No policy: only the functions below read them.
create table if not exists "app_private"."identity_link_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "kind" text not null check ("kind" in ('email', 'chat')),
  "provider" text check (length("provider") between 1 and 100),
  "code_hash" text not null unique,
  "expires_at" timestamptz not null,
  "used_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists identity_link_codes_user_idx on "app_private"."identity_link_codes" ("user_id");
alter table "app_private"."identity_link_codes" enable row level security;
revoke all on "app_private"."identity_link_codes" from public, anon, authenticated;
grant all on "app_private"."identity_link_codes" to service_role;

-- Issues a one-time code for the caller to hand to the bot or the mail
-- side. Issuing replaces the caller's unused codes for the same kind and
-- provider. Returns the code once.
create or replace function "app_private"."begin_identity_link"(kind text, provider text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_code text := upper(encode(extensions.gen_random_bytes(6), 'hex'));
  v_expires timestamptz := now() + interval '10 minutes';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to link an identity' using errcode = '42501', hint = 'IDENTITY_SIGN_IN_REQUIRED';
  end if;
  if begin_identity_link.kind is null or begin_identity_link.kind not in ('email', 'chat') then
    raise exception 'kind must be email or chat' using errcode = '22023', hint = 'IDENTITY_KIND';
  end if;
  delete from "app_private"."identity_link_codes"
  where "user_id" = v_user and "kind" = begin_identity_link.kind
    and "provider" is not distinct from begin_identity_link.provider
    and "used_at" is null;
  insert into "app_private"."identity_link_codes" ("user_id", "kind", "provider", "code_hash", "expires_at")
  values (v_user, begin_identity_link.kind, begin_identity_link.provider, encode(extensions.digest(convert_to(v_code, 'utf8'), 'sha256'), 'hex'), v_expires);
  return jsonb_build_object('code', v_code, 'expires_at', v_expires);
end;
$$;
revoke execute on function "app_private"."begin_identity_link"(text, text) from public, anon;
grant execute on function "app_private"."begin_identity_link"(text, text) to authenticated, service_role;

-- Binds the identity the bot or mail side saw to the user who issued the
-- code. A used, expired or unknown code, or an identity someone else holds,
-- is refused. Service role only: the caller vouches for the identity.
create or replace function "app_private"."redeem_identity_link"(code text, kind text, provider text, value text, workspace text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code_id uuid;
  v_user uuid;
  v_value text := case when redeem_identity_link.kind = 'email' then lower(trim(redeem_identity_link.value)) else redeem_identity_link.value end;
  v_link "app_private"."identity_links";
begin
  if redeem_identity_link.code is null or v_value is null or length(v_value) = 0 then
    raise exception 'invalid or expired link code' using errcode = '22023', hint = 'IDENTITY_LINK_INVALID';
  end if;
  select "id", "user_id" into v_code_id, v_user
  from "app_private"."identity_link_codes"
  where "code_hash" = encode(extensions.digest(convert_to(upper(regexp_replace(redeem_identity_link.code, '[^0-9A-Za-z]', '', 'g')), 'utf8'), 'sha256'), 'hex')
    and "kind" = redeem_identity_link.kind
    and "provider" is not distinct from redeem_identity_link.provider
    and "used_at" is null
    and "expires_at" > now()
  for update;
  if not found then
    raise exception 'invalid or expired link code' using errcode = '22023', hint = 'IDENTITY_LINK_INVALID';
  end if;
  update "app_private"."identity_link_codes" set "used_at" = now() where "id" = v_code_id;
  select * into v_link from "app_private"."identity_links"
  where "kind" = redeem_identity_link.kind
    and "provider" is not distinct from redeem_identity_link.provider
    and "value" = v_value
    and "workspace" is not distinct from redeem_identity_link.workspace;
  if found then
    if v_link."user_id" is distinct from v_user then
      raise exception 'this identity is linked to someone else' using errcode = '23505', hint = 'IDENTITY_TAKEN';
    end if;
  else
    insert into "app_private"."identity_links" ("kind", "provider", "value", "workspace", "user_id", "source")
    values (redeem_identity_link.kind, redeem_identity_link.provider, v_value, redeem_identity_link.workspace, v_user, 'link')
    returning * into v_link;
  end if;
  return jsonb_build_object('id', v_link."id", 'user_id', v_user);
end;
$$;
revoke execute on function "app_private"."redeem_identity_link"(text, text, text, text, text) from public, anon, authenticated;
grant execute on function "app_private"."redeem_identity_link"(text, text, text, text, text) to service_role;

-- The link for an identity: {kind: 'user', userId} or {kind: 'contact',
-- contactId}, or null. An email address also matches a row stored without
-- a provider or workspace, such as a verified address.
create or replace function "app_private"."principal_by_identity"(kind text, provider text, value text, workspace text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when "user_id" is not null
    then jsonb_build_object('kind', 'user', 'userId', "user_id")
    else jsonb_build_object('kind', 'contact', 'contactId', "contact_id")
  end
  from "app_private"."identity_links"
  where "kind" = principal_by_identity.kind
    and "value" = case when principal_by_identity.kind = 'email' then lower(trim(principal_by_identity.value)) else principal_by_identity.value end
    and ("provider" is not distinct from principal_by_identity.provider or ("kind" = 'email' and "provider" is null))
    and ("workspace" is not distinct from principal_by_identity.workspace or ("kind" = 'email' and "workspace" is null))
  order by "provider" is null, "workspace" is null
  limit 1
$$;
revoke execute on function "app_private"."principal_by_identity"(text, text, text, text) from public, anon, authenticated;
grant execute on function "app_private"."principal_by_identity"(text, text, text, text) to service_role;

-- Creates the email identity for a user whose address is confirmed. Does
-- nothing for an unconfirmed address or one that is already linked.
create or replace function "app_private"."link_verified_email"(user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_email text;
begin
  select lower(trim(u.email)) into v_email
  from auth.users u
  where u.id = link_verified_email.user_id and u.email_confirmed_at is not null and u.email is not null and length(trim(u.email)) > 0;
  if v_email is null then
    return false;
  end if;
  insert into "app_private"."identity_links" ("kind", "value", "user_id", "source")
  values ('email', v_email, link_verified_email.user_id, 'verified_email')
  on conflict ("kind", "provider", "value", "workspace") do nothing;
  return found;
end;
$$;
revoke execute on function "app_private"."link_verified_email"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."link_verified_email"(uuid) to service_role;

-- Creates the email identities for users confirmed before the module was installed.
create or replace function "app_private"."backfill_verified_emails"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from auth.users u
  where u.email_confirmed_at is not null and "app_private"."link_verified_email"(u.id)
$$;
revoke execute on function "app_private"."backfill_verified_emails"() from public, anon, authenticated;
grant execute on function "app_private"."backfill_verified_emails"() to service_role;

-- The caller's identities, through the read policy.
create or replace function "app_private"."my_identities"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', "id", 'kind', "kind", 'provider', "provider", 'value', "value",
    'workspace', "workspace", 'source', "source", 'created_at', "created_at"
  ) order by "created_at"), '[]'::jsonb)
  from "app_private"."identity_links"
  where "user_id" = (select auth.uid())
$$;
revoke execute on function "app_private"."my_identities"() from public, anon;
grant execute on function "app_private"."my_identities"() to authenticated, service_role;

-- Removes one of the caller's identities, through the delete policy.
create or replace function "app_private"."unlink_identity"(id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from "app_private"."identity_links" where "id" = unlink_identity.id and "user_id" = (select auth.uid());
  return found;
end;
$$;
revoke execute on function "app_private"."unlink_identity"(uuid) from public, anon;
grant execute on function "app_private"."unlink_identity"(uuid) to authenticated, service_role;

-- Keeps the email identity of each user equal to the confirmed address in
-- auth.users. An address another user or contact holds stays theirs.
create or replace function "app_private"."on_auth_user_email"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    if tg_op = 'UPDATE' and old.email is distinct from new.email then
      delete from "app_private"."identity_links"
      where "user_id" = new.id and "kind" = 'email' and "source" = 'verified_email';
    end if;
    perform "app_private"."link_verified_email"(new.id);
  exception when others then
    raise warning 'No email identity for user %: % (SQLSTATE %)', new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
revoke execute on function "app_private"."on_auth_user_email"() from public, anon, authenticated;
drop trigger if exists "bsb_identity_email" on auth.users;
create trigger "bsb_identity_email" after insert or update of email, email_confirmed_at on auth.users
  for each row execute function "app_private"."on_auth_user_email"();

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_089_identities.sql
-- better-supabase module: identities
-- @bsb-block-data identities
-- @bsb-hash sha256:cd6777a400827759d290e0dde0a7d52f5d50f12b8537a48f4be35b8b3a40cf69
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('identities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_089_identities.sql
-- better-supabase module: identities
-- @bsb-block identities@1 managed
-- @bsb-hash sha256:0bfcb3aaf2e23a99bdcbbe061c82eddac614c139744eb44135da5d85bebaf29f
-- Links an email address or a chat user to an app user or a contact. Rows come only from a one-time code the signed-in user issues and the service redeems, or from a confirmed address in auth.users.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Maps an email address or a chat user to an app user or a contact. Rows
-- come from a link code the signed-in user issued and the service redeemed
-- (redeem_identity_link), or from a confirmed address in auth.users
-- (link_verified_email). Users read and delete their own; nobody inserts or
-- updates directly.
create table if not exists "better_supabase"."identity_links" (
  "id" uuid primary key default gen_random_uuid(),
  "kind" text not null check ("kind" in ('email', 'chat')),
  "provider" text check (length("provider") between 1 and 100),
  "value" text not null check (length("value") between 1 and 500),
  "workspace" text check (length("workspace") between 1 and 200),
  "user_id" uuid references auth.users (id) on delete cascade,
  "contact_id" uuid,
  "source" text not null check ("source" in ('link', 'verified_email')),
  "created_at" timestamptz not null default now(),
  constraint identity_links_one_target check (num_nonnulls("user_id", "contact_id") = 1),
  constraint identity_links_email_lower check ("kind" <> 'email' or "value" = lower("value")),
  constraint identity_links_identity_key unique nulls not distinct ("kind", "provider", "value", "workspace")
);
create index if not exists identity_links_user_idx on "better_supabase"."identity_links" ("user_id");
create index if not exists identity_links_contact_idx on "better_supabase"."identity_links" ("contact_id");
alter table "better_supabase"."identity_links" enable row level security;
revoke all on "better_supabase"."identity_links" from public, anon, authenticated;
grant select, delete on "better_supabase"."identity_links" to authenticated;
grant all on "better_supabase"."identity_links" to service_role;
drop policy if exists identity_links_own_read on "better_supabase"."identity_links";
create policy identity_links_own_read on "better_supabase"."identity_links"
  for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists identity_links_own_delete on "better_supabase"."identity_links";
create policy identity_links_own_delete on "better_supabase"."identity_links"
  for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

-- One-time link codes, stored as SHA-256. No policy: only the functions below read them.
create table if not exists "better_supabase"."identity_link_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "kind" text not null check ("kind" in ('email', 'chat')),
  "provider" text check (length("provider") between 1 and 100),
  "code_hash" text not null unique,
  "expires_at" timestamptz not null,
  "used_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists identity_link_codes_user_idx on "better_supabase"."identity_link_codes" ("user_id");
alter table "better_supabase"."identity_link_codes" enable row level security;
revoke all on "better_supabase"."identity_link_codes" from public, anon, authenticated;
grant all on "better_supabase"."identity_link_codes" to service_role;

-- Issues a one-time code for the caller to hand to the bot or the mail
-- side. Issuing replaces the caller's unused codes for the same kind and
-- provider. Returns the code once.
create or replace function "better_supabase"."begin_identity_link"(kind text, provider text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_code text := upper(encode(extensions.gen_random_bytes(6), 'hex'));
  v_expires timestamptz := now() + interval '10 minutes';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to link an identity' using errcode = '42501', hint = 'IDENTITY_SIGN_IN_REQUIRED';
  end if;
  if begin_identity_link.kind is null or begin_identity_link.kind not in ('email', 'chat') then
    raise exception 'kind must be email or chat' using errcode = '22023', hint = 'IDENTITY_KIND';
  end if;
  delete from "better_supabase"."identity_link_codes"
  where "user_id" = v_user and "kind" = begin_identity_link.kind
    and "provider" is not distinct from begin_identity_link.provider
    and "used_at" is null;
  insert into "better_supabase"."identity_link_codes" ("user_id", "kind", "provider", "code_hash", "expires_at")
  values (v_user, begin_identity_link.kind, begin_identity_link.provider, encode(extensions.digest(convert_to(v_code, 'utf8'), 'sha256'), 'hex'), v_expires);
  return jsonb_build_object('code', v_code, 'expires_at', v_expires);
end;
$$;
revoke execute on function "better_supabase"."begin_identity_link"(text, text) from public, anon;
grant execute on function "better_supabase"."begin_identity_link"(text, text) to authenticated, service_role;

-- Binds the identity the bot or mail side saw to the user who issued the
-- code. A used, expired or unknown code, or an identity someone else holds,
-- is refused. Service role only: the caller vouches for the identity.
create or replace function "better_supabase"."redeem_identity_link"(code text, kind text, provider text, value text, workspace text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code_id uuid;
  v_user uuid;
  v_value text := case when redeem_identity_link.kind = 'email' then lower(trim(redeem_identity_link.value)) else redeem_identity_link.value end;
  v_link "better_supabase"."identity_links";
begin
  if redeem_identity_link.code is null or v_value is null or length(v_value) = 0 then
    raise exception 'invalid or expired link code' using errcode = '22023', hint = 'IDENTITY_LINK_INVALID';
  end if;
  select "id", "user_id" into v_code_id, v_user
  from "better_supabase"."identity_link_codes"
  where "code_hash" = encode(extensions.digest(convert_to(upper(regexp_replace(redeem_identity_link.code, '[^0-9A-Za-z]', '', 'g')), 'utf8'), 'sha256'), 'hex')
    and "kind" = redeem_identity_link.kind
    and "provider" is not distinct from redeem_identity_link.provider
    and "used_at" is null
    and "expires_at" > now()
  for update;
  if not found then
    raise exception 'invalid or expired link code' using errcode = '22023', hint = 'IDENTITY_LINK_INVALID';
  end if;
  update "better_supabase"."identity_link_codes" set "used_at" = now() where "id" = v_code_id;
  select * into v_link from "better_supabase"."identity_links"
  where "kind" = redeem_identity_link.kind
    and "provider" is not distinct from redeem_identity_link.provider
    and "value" = v_value
    and "workspace" is not distinct from redeem_identity_link.workspace;
  if found then
    if v_link."user_id" is distinct from v_user then
      raise exception 'this identity is linked to someone else' using errcode = '23505', hint = 'IDENTITY_TAKEN';
    end if;
  else
    insert into "better_supabase"."identity_links" ("kind", "provider", "value", "workspace", "user_id", "source")
    values (redeem_identity_link.kind, redeem_identity_link.provider, v_value, redeem_identity_link.workspace, v_user, 'link')
    returning * into v_link;
  end if;
  return jsonb_build_object('id', v_link."id", 'user_id', v_user);
end;
$$;
revoke execute on function "better_supabase"."redeem_identity_link"(text, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."redeem_identity_link"(text, text, text, text, text) to service_role;

-- The link for an identity: {kind: 'user', userId} or {kind: 'contact',
-- contactId}, or null. An email address also matches a row stored without
-- a provider or workspace, such as a verified address.
create or replace function "better_supabase"."principal_by_identity"(kind text, provider text, value text, workspace text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when "user_id" is not null
    then jsonb_build_object('kind', 'user', 'userId', "user_id")
    else jsonb_build_object('kind', 'contact', 'contactId', "contact_id")
  end
  from "better_supabase"."identity_links"
  where "kind" = principal_by_identity.kind
    and "value" = case when principal_by_identity.kind = 'email' then lower(trim(principal_by_identity.value)) else principal_by_identity.value end
    and ("provider" is not distinct from principal_by_identity.provider or ("kind" = 'email' and "provider" is null))
    and ("workspace" is not distinct from principal_by_identity.workspace or ("kind" = 'email' and "workspace" is null))
  order by "provider" is null, "workspace" is null
  limit 1
$$;
revoke execute on function "better_supabase"."principal_by_identity"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."principal_by_identity"(text, text, text, text) to service_role;

-- Creates the email identity for a user whose address is confirmed. Does
-- nothing for an unconfirmed address or one that is already linked.
create or replace function "better_supabase"."link_verified_email"(user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_email text;
begin
  select lower(trim(u.email)) into v_email
  from auth.users u
  where u.id = link_verified_email.user_id and u.email_confirmed_at is not null and u.email is not null and length(trim(u.email)) > 0;
  if v_email is null then
    return false;
  end if;
  insert into "better_supabase"."identity_links" ("kind", "value", "user_id", "source")
  values ('email', v_email, link_verified_email.user_id, 'verified_email')
  on conflict ("kind", "provider", "value", "workspace") do nothing;
  return found;
end;
$$;
revoke execute on function "better_supabase"."link_verified_email"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."link_verified_email"(uuid) to service_role;

-- Creates the email identities for users confirmed before the module was installed.
create or replace function "better_supabase"."backfill_verified_emails"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from auth.users u
  where u.email_confirmed_at is not null and "better_supabase"."link_verified_email"(u.id)
$$;
revoke execute on function "better_supabase"."backfill_verified_emails"() from public, anon, authenticated;
grant execute on function "better_supabase"."backfill_verified_emails"() to service_role;

-- The caller's identities, through the read policy.
create or replace function "better_supabase"."my_identities"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', "id", 'kind', "kind", 'provider', "provider", 'value', "value",
    'workspace', "workspace", 'source', "source", 'created_at', "created_at"
  ) order by "created_at"), '[]'::jsonb)
  from "better_supabase"."identity_links"
  where "user_id" = (select auth.uid())
$$;
revoke execute on function "better_supabase"."my_identities"() from public, anon;
grant execute on function "better_supabase"."my_identities"() to authenticated, service_role;

-- Removes one of the caller's identities, through the delete policy.
create or replace function "better_supabase"."unlink_identity"(id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from "better_supabase"."identity_links" where "id" = unlink_identity.id and "user_id" = (select auth.uid());
  return found;
end;
$$;
revoke execute on function "better_supabase"."unlink_identity"(uuid) from public, anon;
grant execute on function "better_supabase"."unlink_identity"(uuid) to authenticated, service_role;

-- Keeps the email identity of each user equal to the confirmed address in
-- auth.users. An address another user or contact holds stays theirs.
create or replace function "better_supabase"."on_auth_user_email"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    if tg_op = 'UPDATE' and old.email is distinct from new.email then
      delete from "better_supabase"."identity_links"
      where "user_id" = new.id and "kind" = 'email' and "source" = 'verified_email';
    end if;
    perform "better_supabase"."link_verified_email"(new.id);
  exception when others then
    raise warning 'No email identity for user %: % (SQLSTATE %)', new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
revoke execute on function "better_supabase"."on_auth_user_email"() from public, anon, authenticated;
drop trigger if exists "bsb_identity_email" on auth.users;
create trigger "bsb_identity_email" after insert or update of email, email_confirmed_at on auth.users
  for each row execute function "better_supabase"."on_auth_user_email"();

-- blocks.identities.api: entry points for the Data API.
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

create or replace function "api"."begin_identity_link"(kind text, provider text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."begin_identity_link"($1, $2) $$;
revoke execute on function "api"."begin_identity_link"(text, text) from public, anon;
grant execute on function "api"."begin_identity_link"(text, text) to authenticated, service_role;

create or replace function "api"."redeem_identity_link"(code text, kind text, provider text, value text, workspace text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."redeem_identity_link"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."redeem_identity_link"(text, text, text, text, text) from public, anon, authenticated;
grant execute on function "api"."redeem_identity_link"(text, text, text, text, text) to service_role;

create or replace function "api"."principal_by_identity"(kind text, provider text, value text, workspace text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."principal_by_identity"($1, $2, $3, $4) $$;
revoke execute on function "api"."principal_by_identity"(text, text, text, text) from public, anon, authenticated;
grant execute on function "api"."principal_by_identity"(text, text, text, text) to service_role;

create or replace function "api"."link_verified_email"(user_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."link_verified_email"($1) $$;
revoke execute on function "api"."link_verified_email"(uuid) from public, anon, authenticated;
grant execute on function "api"."link_verified_email"(uuid) to service_role;

create or replace function "api"."backfill_verified_emails"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."backfill_verified_emails"() $$;
revoke execute on function "api"."backfill_verified_emails"() from public, anon, authenticated;
grant execute on function "api"."backfill_verified_emails"() to service_role;

create or replace function "api"."my_identities"()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."my_identities"() $$;
revoke execute on function "api"."my_identities"() from public, anon;
grant execute on function "api"."my_identities"() to authenticated, service_role;

create or replace function "api"."unlink_identity"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unlink_identity"($1) $$;
revoke execute on function "api"."unlink_identity"(uuid) from public, anon;
grant execute on function "api"."unlink_identity"(uuid) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_089_identities.sql
-- better-supabase module: identities
-- @bsb-block-data identities
-- @bsb-hash sha256:cd6777a400827759d290e0dde0a7d52f5d50f12b8537a48f4be35b8b3a40cf69
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('identities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_089_identities.sql
-- better-supabase module: identities
-- @bsb-block identities@1 managed
-- @bsb-hash sha256:e8c928c4ea2f073450f80add3d2446444f0d3fdaa06b395ce63c1d3ab95f845f
-- Links an email address or a chat user to an app user or a contact. Rows come only from a one-time code the signed-in user issues and the service redeems, or from a confirmed address in auth.users.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.try_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  result alias for $0;
begin
  result := value;
  return result;
exception when data_exception or check_violation then
  return null;
end;
$$;
revoke execute on function better_supabase.try_column_type(text, anyelement) from public;
grant execute on function better_supabase.try_column_type(text, anyelement) to anon, authenticated, service_role;

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
-- Maps an email address or a chat user to an app user or a contact. Rows
-- come from a link code the signed-in user issued and the service redeemed
-- (redeem_identity_link), or from a confirmed address in auth.users
-- (link_verified_email). Users read and delete their own; nobody inserts or
-- updates directly.
-- better_supabase.identity_links is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."identity_links" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."identity_links" add column if not exists "kind" text check ("kind" in ('email', 'chat'));
alter table "better_supabase"."identity_links" add column if not exists "provider" text check (length("provider") between 1 and 100);
alter table "better_supabase"."identity_links" add column if not exists "value" text check (length("value") between 1 and 500);
alter table "better_supabase"."identity_links" add column if not exists "workspace" text check (length("workspace") between 1 and 200);
alter table "better_supabase"."identity_links" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."identity_links" add column if not exists "contact_id" uuid;
alter table "better_supabase"."identity_links" add column if not exists "source" text check ("source" in ('link', 'verified_email'));
alter table "better_supabase"."identity_links" add column if not exists "created_at" timestamptz not null default now();
create index if not exists identity_links_user_idx on "better_supabase"."identity_links" ("user_id");
create index if not exists identity_links_contact_idx on "better_supabase"."identity_links" ("contact_id");
create unique index if not exists "bsb_identity_links_identity_key" on "better_supabase"."identity_links" ("kind", "provider", "value", "workspace") nulls not distinct;
alter table "better_supabase"."identity_links" enable row level security;
grant select, delete on "better_supabase"."identity_links" to authenticated;
grant all on "better_supabase"."identity_links" to service_role;
drop policy if exists bsb_identity_links_select on "better_supabase"."identity_links";
create policy bsb_identity_links_select on "better_supabase"."identity_links"
  for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists bsb_identity_links_delete on "better_supabase"."identity_links";
create policy bsb_identity_links_delete on "better_supabase"."identity_links"
  for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));

-- One-time link codes, stored as SHA-256. No policy: only the functions below read them.
-- better_supabase.identity_link_codes is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."identity_link_codes" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."identity_link_codes" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."identity_link_codes" add column if not exists "kind" text check ("kind" in ('email', 'chat'));
alter table "better_supabase"."identity_link_codes" add column if not exists "provider" text check (length("provider") between 1 and 100);
alter table "better_supabase"."identity_link_codes" add column if not exists "code_hash" text;
alter table "better_supabase"."identity_link_codes" add column if not exists "expires_at" timestamptz;
alter table "better_supabase"."identity_link_codes" add column if not exists "used_at" timestamptz;
alter table "better_supabase"."identity_link_codes" add column if not exists "created_at" timestamptz not null default now();
create index if not exists identity_link_codes_user_idx on "better_supabase"."identity_link_codes" ("user_id");
alter table "better_supabase"."identity_link_codes" enable row level security;
grant all on "better_supabase"."identity_link_codes" to service_role;

-- Issues a one-time code for the caller to hand to the bot or the mail
-- side. Issuing replaces the caller's unused codes for the same kind and
-- provider. Returns the code once.
create or replace function "better_supabase"."begin_identity_link"(kind text, provider text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_code text := upper(encode(extensions.gen_random_bytes(6), 'hex'));
  v_expires timestamptz := now() + interval '10 minutes';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to link an identity' using errcode = '42501', hint = 'IDENTITY_SIGN_IN_REQUIRED';
  end if;
  if begin_identity_link.kind is null or begin_identity_link.kind not in ('email', 'chat') then
    raise exception 'kind must be email or chat' using errcode = '22023', hint = 'IDENTITY_KIND';
  end if;
  delete from "better_supabase"."identity_link_codes"
  where "user_id" = v_user and "kind" = better_supabase.as_column_type(begin_identity_link.kind, (null::"better_supabase"."identity_link_codes")."kind")
    and "provider" is not distinct from begin_identity_link.provider
    and "used_at" is null;
  insert into "better_supabase"."identity_link_codes" ("user_id", "kind", "provider", "code_hash", "expires_at")
  values (v_user, better_supabase.as_column_type(begin_identity_link.kind, (null::"better_supabase"."identity_link_codes")."kind"), begin_identity_link.provider, encode(extensions.digest(convert_to(v_code, 'utf8'), 'sha256'), 'hex'), v_expires);
  return jsonb_build_object('code', v_code, 'expires_at', v_expires);
end;
$$;
revoke execute on function "better_supabase"."begin_identity_link"(text, text) from public, anon;
grant execute on function "better_supabase"."begin_identity_link"(text, text) to authenticated, service_role;

-- Binds the identity the bot or mail side saw to the user who issued the
-- code. A used, expired or unknown code, or an identity someone else holds,
-- is refused. Service role only: the caller vouches for the identity.
create or replace function "better_supabase"."redeem_identity_link"(code text, kind text, provider text, value text, workspace text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code_id uuid;
  v_user uuid;
  v_value text := case when redeem_identity_link.kind = 'email' then lower(trim(redeem_identity_link.value)) else redeem_identity_link.value end;
  v_link "better_supabase"."identity_links";
begin
  if redeem_identity_link.code is null or v_value is null or length(v_value) = 0 then
    raise exception 'invalid or expired link code' using errcode = '22023', hint = 'IDENTITY_LINK_INVALID';
  end if;
  select "id", "user_id" into v_code_id, v_user
  from "better_supabase"."identity_link_codes"
  where "code_hash" = encode(extensions.digest(convert_to(upper(regexp_replace(redeem_identity_link.code, '[^0-9A-Za-z]', '', 'g')), 'utf8'), 'sha256'), 'hex')
    and "kind" = better_supabase.try_column_type(redeem_identity_link.kind, (null::"better_supabase"."identity_link_codes")."kind")
    and "provider" is not distinct from redeem_identity_link.provider
    and "used_at" is null
    and "expires_at" > now()
  for update;
  if not found then
    raise exception 'invalid or expired link code' using errcode = '22023', hint = 'IDENTITY_LINK_INVALID';
  end if;
  update "better_supabase"."identity_link_codes" set "used_at" = now() where "id" = v_code_id;
  select * into v_link from "better_supabase"."identity_links"
  where "kind" = better_supabase.as_column_type(redeem_identity_link.kind, (null::"better_supabase"."identity_links")."kind")
    and "provider" is not distinct from redeem_identity_link.provider
    and "value" = v_value
    and "workspace" is not distinct from redeem_identity_link.workspace;
  if found then
    if v_link."user_id" is distinct from v_user then
      raise exception 'this identity is linked to someone else' using errcode = '23505', hint = 'IDENTITY_TAKEN';
    end if;
  else
    insert into "better_supabase"."identity_links" ("kind", "provider", "value", "workspace", "user_id", "source")
    values (better_supabase.as_column_type(redeem_identity_link.kind, (null::"better_supabase"."identity_links")."kind"), redeem_identity_link.provider, v_value, redeem_identity_link.workspace, v_user, better_supabase.as_column_type('link', (null::"better_supabase"."identity_links")."source"))
    returning * into v_link;
  end if;
  return jsonb_build_object('id', v_link."id", 'user_id', v_user);
end;
$$;
revoke execute on function "better_supabase"."redeem_identity_link"(text, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."redeem_identity_link"(text, text, text, text, text) to service_role;

-- The link for an identity: {kind: 'user', userId} or {kind: 'contact',
-- contactId}, or null. An email address also matches a row stored without
-- a provider or workspace, such as a verified address.
create or replace function "better_supabase"."principal_by_identity"(kind text, provider text, value text, workspace text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when "user_id" is not null
    then jsonb_build_object('kind', 'user', 'userId', "user_id")
    else jsonb_build_object('kind', 'contact', 'contactId', "contact_id")
  end
  from "better_supabase"."identity_links"
  where "kind" = better_supabase.try_column_type(principal_by_identity.kind, (null::"better_supabase"."identity_links")."kind")
    and "value" = case when principal_by_identity.kind = 'email' then lower(trim(principal_by_identity.value)) else principal_by_identity.value end
    and ("provider" is not distinct from principal_by_identity.provider or ("kind" = 'email' and "provider" is null))
    and ("workspace" is not distinct from principal_by_identity.workspace or ("kind" = 'email' and "workspace" is null))
  order by "provider" is null, "workspace" is null
  limit 1
$$;
revoke execute on function "better_supabase"."principal_by_identity"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."principal_by_identity"(text, text, text, text) to service_role;

-- Creates the email identity for a user whose address is confirmed. Does
-- nothing for an unconfirmed address or one that is already linked.
create or replace function "better_supabase"."link_verified_email"(user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_email text;
begin
  select lower(trim(u.email)) into v_email
  from auth.users u
  where u.id = link_verified_email.user_id and u.email_confirmed_at is not null and u.email is not null and length(trim(u.email)) > 0;
  if v_email is null then
    return false;
  end if;
  insert into "better_supabase"."identity_links" ("kind", "value", "user_id", "source")
  values (better_supabase.as_column_type('email', (null::"better_supabase"."identity_links")."kind"), v_email, link_verified_email.user_id, better_supabase.as_column_type('verified_email', (null::"better_supabase"."identity_links")."source"))
  on conflict ("kind", "provider", "value", "workspace") do nothing;
  return found;
end;
$$;
revoke execute on function "better_supabase"."link_verified_email"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."link_verified_email"(uuid) to service_role;

-- Creates the email identities for users confirmed before the module was installed.
create or replace function "better_supabase"."backfill_verified_emails"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from auth.users u
  where u.email_confirmed_at is not null and "better_supabase"."link_verified_email"(u.id)
$$;
revoke execute on function "better_supabase"."backfill_verified_emails"() from public, anon, authenticated;
grant execute on function "better_supabase"."backfill_verified_emails"() to service_role;

-- The caller's identities, through the read policy.
create or replace function "better_supabase"."my_identities"()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', "id", 'kind', "kind", 'provider', "provider", 'value', "value",
    'workspace', "workspace", 'source', "source", 'created_at', "created_at"
  ) order by "created_at"), '[]'::jsonb)
  from "better_supabase"."identity_links"
  where "user_id" = (select auth.uid())
$$;
revoke execute on function "better_supabase"."my_identities"() from public, anon;
grant execute on function "better_supabase"."my_identities"() to authenticated, service_role;

-- Removes one of the caller's identities, through the delete policy.
create or replace function "better_supabase"."unlink_identity"(id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from "better_supabase"."identity_links" where "id" = unlink_identity.id and "user_id" = (select auth.uid());
  return found;
end;
$$;
revoke execute on function "better_supabase"."unlink_identity"(uuid) from public, anon;
grant execute on function "better_supabase"."unlink_identity"(uuid) to authenticated, service_role;

-- Keeps the email identity of each user equal to the confirmed address in
-- auth.users. An address another user or contact holds stays theirs.
create or replace function "better_supabase"."on_auth_user_email"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    if tg_op = 'UPDATE' and old.email is distinct from new.email then
      delete from "better_supabase"."identity_links"
      where "user_id" = new.id and "kind" = 'email' and "source" = 'verified_email';
    end if;
    perform "better_supabase"."link_verified_email"(new.id);
  exception when others then
    raise warning 'No email identity for user %: % (SQLSTATE %)', new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
revoke execute on function "better_supabase"."on_auth_user_email"() from public, anon, authenticated;
drop trigger if exists "bsb_identity_email" on auth.users;
create trigger "bsb_identity_email" after insert or update of email, email_confirmed_at on auth.users
  for each row execute function "better_supabase"."on_auth_user_email"();

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_089_identities.sql
-- better-supabase module: identities
-- @bsb-block-data identities
-- @bsb-hash sha256:cd6777a400827759d290e0dde0a7d52f5d50f12b8537a48f4be35b8b3a40cf69
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('identities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
