-- ==== alone: schema supabase/schemas/900_better_supabase_022_profiles.sql
-- better-supabase module: profiles
-- @bsb-block profiles@2 managed
-- @bsb-hash sha256:98e091680094e1590a2f9b1eff9c40eeeda4a8a5f3ecc7bc00c5069925d9ed9e
-- A profile per user, created on sign-up from auth metadata with a unique username, an email mirror, column-level update grants and a guard on columns the service owns.
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
create table if not exists "better_supabase"."profiles" (
  "id" uuid primary key references auth.users (id) on delete cascade,
  "email" text,
  "username" text,
  "full_name" text,
  "first_name" text,
  "last_name" text,
  "avatar_url" text,
  "avatar_path" text,
  "active_organization_id" uuid,
  "active_team_id" uuid,
  "onboarding" jsonb not null default '{}',
  "disabled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."profiles" add column if not exists "avatar_path" text;

create unique index if not exists profiles_username_idx on "better_supabase"."profiles" (lower("username"));
alter table "better_supabase"."profiles" drop constraint if exists profiles_username_check;
alter table "better_supabase"."profiles" add constraint profiles_username_check check (
  "username" is null or (
    length("username") >= 3
    and length("username") <= 32
    and "username" ~* '^[a-z][a-z0-9_]*$'
    and lower("username") <> all (array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www'])
  )
) not valid;
do $$
begin
  alter table "better_supabase"."profiles" validate constraint profiles_username_check;
exception when check_violation then
  raise warning '% has usernames that break profiles_username_check, so only new ones are checked', '"better_supabase"."profiles"';
end;
$$;
alter table "better_supabase"."profiles" enable row level security;
drop policy if exists bsb_profiles_read on "better_supabase"."profiles";
create policy bsb_profiles_read on "better_supabase"."profiles" for select to authenticated
  using ("id" = (select auth.uid()));
drop policy if exists bsb_profiles_update on "better_supabase"."profiles";
create policy bsb_profiles_update on "better_supabase"."profiles" for update to authenticated
  using (("id" = (select auth.uid())) and (select better_supabase.actor_may_write()))
  with check (("id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
grant select on "better_supabase"."profiles" to authenticated;
grant all on "better_supabase"."profiles" to service_role;


-- Users update only these columns; the rest go through the module's functions.
revoke update on "better_supabase"."profiles" from authenticated;
grant update ("full_name", "first_name", "last_name", "avatar_url", "avatar_path", "username", "onboarding", "updated_at") on "better_supabase"."profiles" to authenticated;

-- The API roles can't change the key or "email", "disabled_at", "active_organization_id", "active_team_id", "created_at". Security
-- definer functions (switch_organization, the email mirror) run as their
-- owner and pass.
create or replace function "better_supabase"."guard_profile"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and (
    new."id" is distinct from old."id"
    or new."email" is distinct from old."email"
    or new."disabled_at" is distinct from old."disabled_at"
    or new."active_organization_id" is distinct from old."active_organization_id"
    or new."active_team_id" is distinct from old."active_team_id"
    or new."created_at" is distinct from old."created_at"
  ) then
    raise exception 'These profile columns are managed by the service' using errcode = '42501', hint = 'PROFILE_COLUMN_READONLY';
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function "better_supabase"."guard_profile"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_guard" on "better_supabase"."profiles";
create trigger "bsb_profile_guard" before update on "better_supabase"."profiles"
  for each row execute function "better_supabase"."guard_profile"();

-- A free username from base: lowercased, stripped to [a-z0-9_], starting
-- with a letter, then suffixed with a number while it is reserved or
-- another profile has it.
create or replace function "better_supabase"."allocate_username"(base text, user_id uuid default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  stem text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]+', '', 'g'), 28);
  candidate text;
  n integer := 0;
begin
  if stem !~ '^[a-z]' then
    stem := left('u' || stem, 28);
  end if;
  if length(stem) < 3 then
    stem := 'user';
  end if;
  candidate := stem;
  while candidate = any(array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www']) or exists (
    select 1 from "better_supabase"."profiles" p
    where lower(p."username") = candidate and p."id" is distinct from user_id
  ) loop
    n := n + 1;
    candidate := stem || n::text;
  end loop;
  return candidate;
end;
$$;
revoke execute on function "better_supabase"."allocate_username"(text, uuid) from public, anon;
grant execute on function "better_supabase"."allocate_username"(text, uuid) to authenticated, service_role;

-- Creates the user's profile from auth.users when it has none: metadata
-- keys (blocks.profiles.options.metadata), the email and a username. The
-- after_profile_sync hook runs only for a profile it created.
create or replace function "better_supabase"."sync_profile"(user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  u auth.users;
  meta jsonb;
  created boolean := false;
  attempt integer := 0;
begin
  select * into u from auth.users where id = user_id;
  if not found then
    return false;
  end if;
  meta := coalesce(u.raw_user_meta_data, '{}');
  if not exists (select 1 from "better_supabase"."profiles" p where p."id" = user_id) then
    loop
      begin
        insert into "better_supabase"."profiles" ("id", "full_name", "first_name", "last_name", "avatar_url", "email", "username")
        values (user_id, coalesce(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), nullif(concat_ws(' ', nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), '')), '')), coalesce(nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1), '')), coalesce(nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), ''), nullif(btrim(substr(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), length(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1)) + 1)), '')), nullif(btrim(coalesce(meta ->> 'avatar_url', meta ->> 'picture')), ''), u.email, "better_supabase"."allocate_username"(coalesce(nullif(btrim(coalesce(meta ->> 'user_name', meta ->> 'preferred_username', meta ->> 'username')), ''), split_part(u.email, '@', 1)), user_id));
        created := true;
        exit;
      exception when unique_violation then
        -- Another sign-up took the username between allocation and insert.
        attempt := attempt + 1;
        if attempt >= 3 or exists (select 1 from "better_supabase"."profiles" p where p."id" = user_id) then
          exit;
        end if;
      end;
    end loop;
  end if;
  if created then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_sync"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using user_id;
      end if;
    end;
  end if;
  return created;
end;
$$;
revoke execute on function "better_supabase"."sync_profile"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_profile"(uuid) to service_role;

-- Profiles for users that have none, after installing on an existing project.
create or replace function "better_supabase"."backfill_profiles"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from auth.users u where "better_supabase"."sync_profile"(u.id)
$$;
revoke execute on function "better_supabase"."backfill_profiles"() from public, anon, authenticated;
grant execute on function "better_supabase"."backfill_profiles"() to service_role;

drop function if exists "better_supabase"."my_profile"();
create or replace function "better_supabase"."my_profile"()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(p) from "better_supabase"."profiles" p where p."id" = (select auth.uid())
$$;
revoke execute on function "better_supabase"."my_profile"() from public, anon;
grant execute on function "better_supabase"."my_profile"() to authenticated, service_role;

create or replace function "better_supabase"."update_my_profile"(attrs jsonb)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  updated integer;
  v_caller uuid := (select auth.uid());
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_profile_update"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, v_caller;
    end if;
  end;
  update "better_supabase"."profiles" p
  set "full_name" = case when update_my_profile.attrs ? 'full_name' then update_my_profile.attrs ->> 'full_name' else p."full_name" end,
    "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "avatar_url" = case when update_my_profile.attrs ? 'avatar_url' then update_my_profile.attrs ->> 'avatar_url' else p."avatar_url" end,
    "avatar_path" = case when update_my_profile.attrs ? 'avatar_path' then update_my_profile.attrs ->> 'avatar_path' else p."avatar_path" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "onboarding" = case when update_my_profile.attrs ? 'onboarding' then update_my_profile.attrs -> 'onboarding' else p."onboarding" end,
    "updated_at" = now()
  where p."id" = v_caller;
  get diagnostics updated = row_count;
  if updated > 0 then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_update"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using v_caller;
      end if;
    end;
  end if;
  return updated > 0;
end;
$$;
revoke execute on function "better_supabase"."update_my_profile"(jsonb) from public, anon;
grant execute on function "better_supabase"."update_my_profile"(jsonb) to authenticated, service_role;

create or replace function better_supabase.replace_equivalent_triggers(
  target regclass,
  module_trigger text,
  pattern text,
  replace_trigger boolean
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  found record;
begin
  for found in
    select t.tgname as name, p.proname as fn
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = replace_equivalent_triggers.target
      and not t.tgisinternal
      and t.tgname <> replace_equivalent_triggers.module_trigger
      and p.proname ~* replace_equivalent_triggers.pattern
  loop
    if replace_trigger then
      execute format('drop trigger %I on %s', found.name, target);
    else
      raise warning '% already has trigger % (%), which does what % does. Pass replace_trigger => true to drop it.',
        target, found.name, found.fn, module_trigger;
    end if;
  end loop;
end;
$$;
revoke execute on function better_supabase.replace_equivalent_triggers(regclass, text, text, boolean) from public, anon, authenticated;

create or replace function "better_supabase"."on_auth_user_created"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A failure here would abort the sign-up. The user gets an account
  -- without a profile instead, and backfill_profiles() creates it later.
  begin
    perform "better_supabase"."sync_profile"(new.id);
  exception when others then
    raise warning 'No profile for user %: % (SQLSTATE %). Run backfill_profiles() once it is fixed.',
      new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
revoke execute on function "better_supabase"."on_auth_user_created"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_sync" on auth.users;
create trigger "bsb_profile_sync" after insert on auth.users
  for each row execute function "better_supabase"."on_auth_user_created"();

-- Keeps the profile's email equal to the confirmed address in auth.users.
create or replace function "better_supabase"."mirror_profile_email"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."profiles" set "email" = new.email where "id" = new.id and "email" is distinct from new.email;
  return new;
end;
$$;
revoke execute on function "better_supabase"."mirror_profile_email"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_email" on auth.users;
create trigger "bsb_profile_email" after update of email on auth.users
  for each row execute function "better_supabase"."mirror_profile_email"();

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_022_profiles.sql
-- better-supabase module: profiles
-- @bsb-block-data profiles
-- @bsb-hash sha256:45eb922a57d2c451d84537ff0eabe7454ea0b51feab4ae418357c20a37ce6116
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Warns about another trigger that also creates profiles (handle_new_user).
select better_supabase.replace_equivalent_triggers('auth.users', 'bsb_profile_sync', '(handle_new_user|create_profile|new_user_profile)', false);

insert into better_supabase.blocks (name, version, mode)
values ('profiles', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_022_profiles.sql
-- better-supabase module: profiles
-- @bsb-block profiles@2 managed
-- @bsb-hash sha256:98e091680094e1590a2f9b1eff9c40eeeda4a8a5f3ecc7bc00c5069925d9ed9e
-- A profile per user, created on sign-up from auth metadata with a unique username, an email mirror, column-level update grants and a guard on columns the service owns.
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
create table if not exists "better_supabase"."profiles" (
  "id" uuid primary key references auth.users (id) on delete cascade,
  "email" text,
  "username" text,
  "full_name" text,
  "first_name" text,
  "last_name" text,
  "avatar_url" text,
  "avatar_path" text,
  "active_organization_id" uuid,
  "active_team_id" uuid,
  "onboarding" jsonb not null default '{}',
  "disabled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."profiles" add column if not exists "avatar_path" text;

create unique index if not exists profiles_username_idx on "better_supabase"."profiles" (lower("username"));
alter table "better_supabase"."profiles" drop constraint if exists profiles_username_check;
alter table "better_supabase"."profiles" add constraint profiles_username_check check (
  "username" is null or (
    length("username") >= 3
    and length("username") <= 32
    and "username" ~* '^[a-z][a-z0-9_]*$'
    and lower("username") <> all (array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www'])
  )
) not valid;
do $$
begin
  alter table "better_supabase"."profiles" validate constraint profiles_username_check;
exception when check_violation then
  raise warning '% has usernames that break profiles_username_check, so only new ones are checked', '"better_supabase"."profiles"';
end;
$$;
alter table "better_supabase"."profiles" enable row level security;
drop policy if exists bsb_profiles_read on "better_supabase"."profiles";
create policy bsb_profiles_read on "better_supabase"."profiles" for select to authenticated
  using ("id" = (select auth.uid()));
drop policy if exists bsb_profiles_update on "better_supabase"."profiles";
create policy bsb_profiles_update on "better_supabase"."profiles" for update to authenticated
  using (("id" = (select auth.uid())) and (select better_supabase.actor_may_write()))
  with check (("id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
grant select on "better_supabase"."profiles" to authenticated;
grant all on "better_supabase"."profiles" to service_role;


-- Users update only these columns; the rest go through the module's functions.
revoke update on "better_supabase"."profiles" from authenticated;
grant update ("full_name", "first_name", "last_name", "avatar_url", "avatar_path", "username", "onboarding", "updated_at") on "better_supabase"."profiles" to authenticated;

-- The API roles can't change the key or "email", "disabled_at", "active_organization_id", "active_team_id", "created_at". Security
-- definer functions (switch_organization, the email mirror) run as their
-- owner and pass.
create or replace function "better_supabase"."guard_profile"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and (
    new."id" is distinct from old."id"
    or new."email" is distinct from old."email"
    or new."disabled_at" is distinct from old."disabled_at"
    or new."active_organization_id" is distinct from old."active_organization_id"
    or new."active_team_id" is distinct from old."active_team_id"
    or new."created_at" is distinct from old."created_at"
  ) then
    raise exception 'These profile columns are managed by the service' using errcode = '42501', hint = 'PROFILE_COLUMN_READONLY';
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function "better_supabase"."guard_profile"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_guard" on "better_supabase"."profiles";
create trigger "bsb_profile_guard" before update on "better_supabase"."profiles"
  for each row execute function "better_supabase"."guard_profile"();

-- A free username from base: lowercased, stripped to [a-z0-9_], starting
-- with a letter, then suffixed with a number while it is reserved or
-- another profile has it.
create or replace function "better_supabase"."allocate_username"(base text, user_id uuid default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  stem text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]+', '', 'g'), 28);
  candidate text;
  n integer := 0;
begin
  if stem !~ '^[a-z]' then
    stem := left('u' || stem, 28);
  end if;
  if length(stem) < 3 then
    stem := 'user';
  end if;
  candidate := stem;
  while candidate = any(array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www']) or exists (
    select 1 from "better_supabase"."profiles" p
    where lower(p."username") = candidate and p."id" is distinct from user_id
  ) loop
    n := n + 1;
    candidate := stem || n::text;
  end loop;
  return candidate;
end;
$$;
revoke execute on function "better_supabase"."allocate_username"(text, uuid) from public, anon;
grant execute on function "better_supabase"."allocate_username"(text, uuid) to authenticated, service_role;

-- Creates the user's profile from auth.users when it has none: metadata
-- keys (blocks.profiles.options.metadata), the email and a username. The
-- after_profile_sync hook runs only for a profile it created.
create or replace function "better_supabase"."sync_profile"(user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  u auth.users;
  meta jsonb;
  created boolean := false;
  attempt integer := 0;
begin
  select * into u from auth.users where id = user_id;
  if not found then
    return false;
  end if;
  meta := coalesce(u.raw_user_meta_data, '{}');
  if not exists (select 1 from "better_supabase"."profiles" p where p."id" = user_id) then
    loop
      begin
        insert into "better_supabase"."profiles" ("id", "full_name", "first_name", "last_name", "avatar_url", "email", "username")
        values (user_id, coalesce(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), nullif(concat_ws(' ', nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), '')), '')), coalesce(nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1), '')), coalesce(nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), ''), nullif(btrim(substr(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), length(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1)) + 1)), '')), nullif(btrim(coalesce(meta ->> 'avatar_url', meta ->> 'picture')), ''), u.email, "better_supabase"."allocate_username"(coalesce(nullif(btrim(coalesce(meta ->> 'user_name', meta ->> 'preferred_username', meta ->> 'username')), ''), split_part(u.email, '@', 1)), user_id));
        created := true;
        exit;
      exception when unique_violation then
        -- Another sign-up took the username between allocation and insert.
        attempt := attempt + 1;
        if attempt >= 3 or exists (select 1 from "better_supabase"."profiles" p where p."id" = user_id) then
          exit;
        end if;
      end;
    end loop;
  end if;
  if created then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_sync"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using user_id;
      end if;
    end;
  end if;
  return created;
end;
$$;
revoke execute on function "better_supabase"."sync_profile"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_profile"(uuid) to service_role;

-- Profiles for users that have none, after installing on an existing project.
create or replace function "better_supabase"."backfill_profiles"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from auth.users u where "better_supabase"."sync_profile"(u.id)
$$;
revoke execute on function "better_supabase"."backfill_profiles"() from public, anon, authenticated;
grant execute on function "better_supabase"."backfill_profiles"() to service_role;

drop function if exists "better_supabase"."my_profile"();
create or replace function "better_supabase"."my_profile"()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(p) from "better_supabase"."profiles" p where p."id" = (select auth.uid())
$$;
revoke execute on function "better_supabase"."my_profile"() from public, anon;
grant execute on function "better_supabase"."my_profile"() to authenticated, service_role;

create or replace function "better_supabase"."update_my_profile"(attrs jsonb)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  updated integer;
  v_caller uuid := (select auth.uid());
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_profile_update"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, v_caller;
    end if;
  end;
  update "better_supabase"."profiles" p
  set "full_name" = case when update_my_profile.attrs ? 'full_name' then update_my_profile.attrs ->> 'full_name' else p."full_name" end,
    "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "avatar_url" = case when update_my_profile.attrs ? 'avatar_url' then update_my_profile.attrs ->> 'avatar_url' else p."avatar_url" end,
    "avatar_path" = case when update_my_profile.attrs ? 'avatar_path' then update_my_profile.attrs ->> 'avatar_path' else p."avatar_path" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "onboarding" = case when update_my_profile.attrs ? 'onboarding' then update_my_profile.attrs -> 'onboarding' else p."onboarding" end,
    "updated_at" = now()
  where p."id" = v_caller;
  get diagnostics updated = row_count;
  if updated > 0 then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_update"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using v_caller;
      end if;
    end;
  end if;
  return updated > 0;
end;
$$;
revoke execute on function "better_supabase"."update_my_profile"(jsonb) from public, anon;
grant execute on function "better_supabase"."update_my_profile"(jsonb) to authenticated, service_role;

create or replace function better_supabase.replace_equivalent_triggers(
  target regclass,
  module_trigger text,
  pattern text,
  replace_trigger boolean
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  found record;
begin
  for found in
    select t.tgname as name, p.proname as fn
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = replace_equivalent_triggers.target
      and not t.tgisinternal
      and t.tgname <> replace_equivalent_triggers.module_trigger
      and p.proname ~* replace_equivalent_triggers.pattern
  loop
    if replace_trigger then
      execute format('drop trigger %I on %s', found.name, target);
    else
      raise warning '% already has trigger % (%), which does what % does. Pass replace_trigger => true to drop it.',
        target, found.name, found.fn, module_trigger;
    end if;
  end loop;
end;
$$;
revoke execute on function better_supabase.replace_equivalent_triggers(regclass, text, text, boolean) from public, anon, authenticated;

create or replace function "better_supabase"."on_auth_user_created"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A failure here would abort the sign-up. The user gets an account
  -- without a profile instead, and backfill_profiles() creates it later.
  begin
    perform "better_supabase"."sync_profile"(new.id);
  exception when others then
    raise warning 'No profile for user %: % (SQLSTATE %). Run backfill_profiles() once it is fixed.',
      new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
revoke execute on function "better_supabase"."on_auth_user_created"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_sync" on auth.users;
create trigger "bsb_profile_sync" after insert on auth.users
  for each row execute function "better_supabase"."on_auth_user_created"();

-- Keeps the profile's email equal to the confirmed address in auth.users.
create or replace function "better_supabase"."mirror_profile_email"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."profiles" set "email" = new.email where "id" = new.id and "email" is distinct from new.email;
  return new;
end;
$$;
revoke execute on function "better_supabase"."mirror_profile_email"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_email" on auth.users;
create trigger "bsb_profile_email" after update of email on auth.users
  for each row execute function "better_supabase"."mirror_profile_email"();

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_022_profiles.sql
-- better-supabase module: profiles
-- @bsb-block-data profiles
-- @bsb-hash sha256:45eb922a57d2c451d84537ff0eabe7454ea0b51feab4ae418357c20a37ce6116
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Warns about another trigger that also creates profiles (handle_new_user).
select better_supabase.replace_equivalent_triggers('auth.users', 'bsb_profile_sync', '(handle_new_user|create_profile|new_user_profile)', false);

insert into better_supabase.blocks (name, version, mode)
values ('profiles', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_022_profiles.sql
-- better-supabase module: profiles
-- @bsb-block profiles@2 managed
-- @bsb-hash sha256:0c10dae3a777c0d9d174eb05682cd8f5401713418a6c146df74ddf1b06d58087
-- A profile per user, created on sign-up from auth metadata with a unique username, an email mirror, column-level update grants and a guard on columns the service owns.
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
create table if not exists "app_private"."profiles" (
  "id" uuid primary key references auth.users (id) on delete cascade,
  "email" text,
  "username" text,
  "full_name" text,
  "first_name" text,
  "last_name" text,
  "avatar_url" text,
  "avatar_path" text,
  "active_organization_id" uuid,
  "active_team_id" uuid,
  "onboarding" jsonb not null default '{}',
  "disabled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "app_private"."profiles" add column if not exists "avatar_path" text;

create unique index if not exists profiles_username_idx on "app_private"."profiles" (lower("username"));
alter table "app_private"."profiles" drop constraint if exists profiles_username_check;
alter table "app_private"."profiles" add constraint profiles_username_check check (
  "username" is null or (
    length("username") >= 3
    and length("username") <= 32
    and "username" ~* '^[a-z][a-z0-9_]*$'
    and lower("username") <> all (array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www'])
  )
) not valid;
do $$
begin
  alter table "app_private"."profiles" validate constraint profiles_username_check;
exception when check_violation then
  raise warning '% has usernames that break profiles_username_check, so only new ones are checked', '"app_private"."profiles"';
end;
$$;
alter table "app_private"."profiles" enable row level security;
drop policy if exists bsb_profiles_read on "app_private"."profiles";
create policy bsb_profiles_read on "app_private"."profiles" for select to authenticated
  using ("id" = (select auth.uid()));
drop policy if exists bsb_profiles_update on "app_private"."profiles";
create policy bsb_profiles_update on "app_private"."profiles" for update to authenticated
  using (("id" = (select auth.uid())) and (select better_supabase.actor_may_write()))
  with check (("id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
grant select on "app_private"."profiles" to authenticated;
grant all on "app_private"."profiles" to service_role;


-- Users update only these columns; the rest go through the module's functions.
revoke update on "app_private"."profiles" from authenticated;
grant update ("full_name", "first_name", "last_name", "avatar_url", "avatar_path", "username", "onboarding", "updated_at") on "app_private"."profiles" to authenticated;

-- The API roles can't change the key or "email", "disabled_at", "active_organization_id", "active_team_id", "created_at". Security
-- definer functions (switch_organization, the email mirror) run as their
-- owner and pass.
create or replace function "app_private"."guard_profile"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and (
    new."id" is distinct from old."id"
    or new."email" is distinct from old."email"
    or new."disabled_at" is distinct from old."disabled_at"
    or new."active_organization_id" is distinct from old."active_organization_id"
    or new."active_team_id" is distinct from old."active_team_id"
    or new."created_at" is distinct from old."created_at"
  ) then
    raise exception 'These profile columns are managed by the service' using errcode = '42501', hint = 'PROFILE_COLUMN_READONLY';
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function "app_private"."guard_profile"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_guard" on "app_private"."profiles";
create trigger "bsb_profile_guard" before update on "app_private"."profiles"
  for each row execute function "app_private"."guard_profile"();

-- A free username from base: lowercased, stripped to [a-z0-9_], starting
-- with a letter, then suffixed with a number while it is reserved or
-- another profile has it.
create or replace function "app_private"."allocate_username"(base text, user_id uuid default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  stem text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]+', '', 'g'), 28);
  candidate text;
  n integer := 0;
begin
  if stem !~ '^[a-z]' then
    stem := left('u' || stem, 28);
  end if;
  if length(stem) < 3 then
    stem := 'user';
  end if;
  candidate := stem;
  while candidate = any(array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www']) or exists (
    select 1 from "app_private"."profiles" p
    where lower(p."username") = candidate and p."id" is distinct from user_id
  ) loop
    n := n + 1;
    candidate := stem || n::text;
  end loop;
  return candidate;
end;
$$;
revoke execute on function "app_private"."allocate_username"(text, uuid) from public, anon;
grant execute on function "app_private"."allocate_username"(text, uuid) to authenticated, service_role;

-- Creates the user's profile from auth.users when it has none: metadata
-- keys (blocks.profiles.options.metadata), the email and a username. The
-- after_profile_sync hook runs only for a profile it created.
create or replace function "app_private"."sync_profile"(user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  u auth.users;
  meta jsonb;
  created boolean := false;
  attempt integer := 0;
begin
  select * into u from auth.users where id = user_id;
  if not found then
    return false;
  end if;
  meta := coalesce(u.raw_user_meta_data, '{}');
  if not exists (select 1 from "app_private"."profiles" p where p."id" = user_id) then
    loop
      begin
        insert into "app_private"."profiles" ("id", "full_name", "first_name", "last_name", "avatar_url", "email", "username")
        values (user_id, coalesce(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), nullif(concat_ws(' ', nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), '')), '')), coalesce(nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1), '')), coalesce(nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), ''), nullif(btrim(substr(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), length(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1)) + 1)), '')), nullif(btrim(coalesce(meta ->> 'avatar_url', meta ->> 'picture')), ''), u.email, "app_private"."allocate_username"(coalesce(nullif(btrim(coalesce(meta ->> 'user_name', meta ->> 'preferred_username', meta ->> 'username')), ''), split_part(u.email, '@', 1)), user_id));
        created := true;
        exit;
      exception when unique_violation then
        -- Another sign-up took the username between allocation and insert.
        attempt := attempt + 1;
        if attempt >= 3 or exists (select 1 from "app_private"."profiles" p where p."id" = user_id) then
          exit;
        end if;
      end;
    end loop;
  end if;
  if created then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_sync"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using user_id;
      end if;
    end;
  end if;
  return created;
end;
$$;
revoke execute on function "app_private"."sync_profile"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."sync_profile"(uuid) to service_role;

-- Profiles for users that have none, after installing on an existing project.
create or replace function "app_private"."backfill_profiles"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from auth.users u where "app_private"."sync_profile"(u.id)
$$;
revoke execute on function "app_private"."backfill_profiles"() from public, anon, authenticated;
grant execute on function "app_private"."backfill_profiles"() to service_role;

drop function if exists "app_private"."my_profile"();
create or replace function "app_private"."my_profile"()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(p) from "app_private"."profiles" p where p."id" = (select auth.uid())
$$;
revoke execute on function "app_private"."my_profile"() from public, anon;
grant execute on function "app_private"."my_profile"() to authenticated, service_role;

create or replace function "app_private"."update_my_profile"(attrs jsonb)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  updated integer;
  v_caller uuid := (select auth.uid());
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_profile_update"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, v_caller;
    end if;
  end;
  update "app_private"."profiles" p
  set "full_name" = case when update_my_profile.attrs ? 'full_name' then update_my_profile.attrs ->> 'full_name' else p."full_name" end,
    "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "avatar_url" = case when update_my_profile.attrs ? 'avatar_url' then update_my_profile.attrs ->> 'avatar_url' else p."avatar_url" end,
    "avatar_path" = case when update_my_profile.attrs ? 'avatar_path' then update_my_profile.attrs ->> 'avatar_path' else p."avatar_path" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "onboarding" = case when update_my_profile.attrs ? 'onboarding' then update_my_profile.attrs -> 'onboarding' else p."onboarding" end,
    "updated_at" = now()
  where p."id" = v_caller;
  get diagnostics updated = row_count;
  if updated > 0 then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_update"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using v_caller;
      end if;
    end;
  end if;
  return updated > 0;
end;
$$;
revoke execute on function "app_private"."update_my_profile"(jsonb) from public, anon;
grant execute on function "app_private"."update_my_profile"(jsonb) to authenticated, service_role;

create or replace function better_supabase.replace_equivalent_triggers(
  target regclass,
  module_trigger text,
  pattern text,
  replace_trigger boolean
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  found record;
begin
  for found in
    select t.tgname as name, p.proname as fn
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = replace_equivalent_triggers.target
      and not t.tgisinternal
      and t.tgname <> replace_equivalent_triggers.module_trigger
      and p.proname ~* replace_equivalent_triggers.pattern
  loop
    if replace_trigger then
      execute format('drop trigger %I on %s', found.name, target);
    else
      raise warning '% already has trigger % (%), which does what % does. Pass replace_trigger => true to drop it.',
        target, found.name, found.fn, module_trigger;
    end if;
  end loop;
end;
$$;
revoke execute on function better_supabase.replace_equivalent_triggers(regclass, text, text, boolean) from public, anon, authenticated;

create or replace function "app_private"."on_auth_user_created"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A failure here would abort the sign-up. The user gets an account
  -- without a profile instead, and backfill_profiles() creates it later.
  begin
    perform "app_private"."sync_profile"(new.id);
  exception when others then
    raise warning 'No profile for user %: % (SQLSTATE %). Run backfill_profiles() once it is fixed.',
      new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
revoke execute on function "app_private"."on_auth_user_created"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_sync" on auth.users;
create trigger "bsb_profile_sync" after insert on auth.users
  for each row execute function "app_private"."on_auth_user_created"();

-- Keeps the profile's email equal to the confirmed address in auth.users.
create or replace function "app_private"."mirror_profile_email"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "app_private"."profiles" set "email" = new.email where "id" = new.id and "email" is distinct from new.email;
  return new;
end;
$$;
revoke execute on function "app_private"."mirror_profile_email"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_email" on auth.users;
create trigger "bsb_profile_email" after update of email on auth.users
  for each row execute function "app_private"."mirror_profile_email"();

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_022_profiles.sql
-- better-supabase module: profiles
-- @bsb-block-data profiles
-- @bsb-hash sha256:45eb922a57d2c451d84537ff0eabe7454ea0b51feab4ae418357c20a37ce6116
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Warns about another trigger that also creates profiles (handle_new_user).
select better_supabase.replace_equivalent_triggers('auth.users', 'bsb_profile_sync', '(handle_new_user|create_profile|new_user_profile)', false);

insert into better_supabase.blocks (name, version, mode)
values ('profiles', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_022_profiles.sql
-- better-supabase module: profiles
-- @bsb-block profiles@2 managed
-- @bsb-hash sha256:0e9e6bc99e2b8a5c74d0a3794179fa62968334aa34c1cffa6b14e9571d333726
-- A profile per user, created on sign-up from auth metadata with a unique username, an email mirror, column-level update grants and a guard on columns the service owns.
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
create table if not exists "better_supabase"."profiles" (
  "id" uuid primary key references auth.users (id) on delete cascade,
  "email" text,
  "username" text,
  "full_name" text,
  "first_name" text,
  "last_name" text,
  "avatar_url" text,
  "avatar_path" text,
  "active_organization_id" uuid,
  "active_team_id" uuid,
  "onboarding" jsonb not null default '{}',
  "disabled_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."profiles" add column if not exists "avatar_path" text;

create unique index if not exists profiles_username_idx on "better_supabase"."profiles" (lower("username"));
alter table "better_supabase"."profiles" drop constraint if exists profiles_username_check;
alter table "better_supabase"."profiles" add constraint profiles_username_check check (
  "username" is null or (
    length("username") >= 3
    and length("username") <= 32
    and "username" ~* '^[a-z][a-z0-9_]*$'
    and lower("username") <> all (array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www'])
  )
) not valid;
do $$
begin
  alter table "better_supabase"."profiles" validate constraint profiles_username_check;
exception when check_violation then
  raise warning '% has usernames that break profiles_username_check, so only new ones are checked', '"better_supabase"."profiles"';
end;
$$;
alter table "better_supabase"."profiles" enable row level security;
drop policy if exists bsb_profiles_read on "better_supabase"."profiles";
create policy bsb_profiles_read on "better_supabase"."profiles" for select to authenticated
  using ("id" = (select auth.uid()));
drop policy if exists bsb_profiles_update on "better_supabase"."profiles";
create policy bsb_profiles_update on "better_supabase"."profiles" for update to authenticated
  using (("id" = (select auth.uid())) and (select better_supabase.actor_may_write()))
  with check (("id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
grant select on "better_supabase"."profiles" to authenticated;
grant all on "better_supabase"."profiles" to service_role;


-- Users update only these columns; the rest go through the module's functions.
revoke update on "better_supabase"."profiles" from authenticated;
grant update ("full_name", "first_name", "last_name", "avatar_url", "avatar_path", "username", "onboarding", "updated_at") on "better_supabase"."profiles" to authenticated;

-- The API roles can't change the key or "email", "disabled_at", "active_organization_id", "active_team_id", "created_at". Security
-- definer functions (switch_organization, the email mirror) run as their
-- owner and pass.
create or replace function "better_supabase"."guard_profile"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and (
    new."id" is distinct from old."id"
    or new."email" is distinct from old."email"
    or new."disabled_at" is distinct from old."disabled_at"
    or new."active_organization_id" is distinct from old."active_organization_id"
    or new."active_team_id" is distinct from old."active_team_id"
    or new."created_at" is distinct from old."created_at"
  ) then
    raise exception 'These profile columns are managed by the service' using errcode = '42501', hint = 'PROFILE_COLUMN_READONLY';
  end if;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function "better_supabase"."guard_profile"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_guard" on "better_supabase"."profiles";
create trigger "bsb_profile_guard" before update on "better_supabase"."profiles"
  for each row execute function "better_supabase"."guard_profile"();

-- A free username from base: lowercased, stripped to [a-z0-9_], starting
-- with a letter, then suffixed with a number while it is reserved or
-- another profile has it.
create or replace function "better_supabase"."allocate_username"(base text, user_id uuid default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  stem text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]+', '', 'g'), 28);
  candidate text;
  n integer := 0;
begin
  if stem !~ '^[a-z]' then
    stem := left('u' || stem, 28);
  end if;
  if length(stem) < 3 then
    stem := 'user';
  end if;
  candidate := stem;
  while candidate = any(array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www']) or exists (
    select 1 from "better_supabase"."profiles" p
    where lower(p."username") = candidate and p."id" is distinct from user_id
  ) loop
    n := n + 1;
    candidate := stem || n::text;
  end loop;
  return candidate;
end;
$$;
revoke execute on function "better_supabase"."allocate_username"(text, uuid) from public, anon;
grant execute on function "better_supabase"."allocate_username"(text, uuid) to authenticated, service_role;

-- Creates the user's profile from auth.users when it has none: metadata
-- keys (blocks.profiles.options.metadata), the email and a username. The
-- after_profile_sync hook runs only for a profile it created.
create or replace function "better_supabase"."sync_profile"(user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  u auth.users;
  meta jsonb;
  created boolean := false;
  attempt integer := 0;
begin
  select * into u from auth.users where id = user_id;
  if not found then
    return false;
  end if;
  meta := coalesce(u.raw_user_meta_data, '{}');
  if not exists (select 1 from "better_supabase"."profiles" p where p."id" = user_id) then
    loop
      begin
        insert into "better_supabase"."profiles" ("id", "full_name", "first_name", "last_name", "avatar_url", "email", "username")
        values (user_id, coalesce(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), nullif(concat_ws(' ', nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), '')), '')), coalesce(nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1), '')), coalesce(nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), ''), nullif(btrim(substr(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), length(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1)) + 1)), '')), nullif(btrim(coalesce(meta ->> 'avatar_url', meta ->> 'picture')), ''), u.email, "better_supabase"."allocate_username"(coalesce(nullif(btrim(coalesce(meta ->> 'user_name', meta ->> 'preferred_username', meta ->> 'username')), ''), split_part(u.email, '@', 1)), user_id));
        created := true;
        exit;
      exception when unique_violation then
        -- Another sign-up took the username between allocation and insert.
        attempt := attempt + 1;
        if attempt >= 3 or exists (select 1 from "better_supabase"."profiles" p where p."id" = user_id) then
          exit;
        end if;
      end;
    end loop;
  end if;
  if created then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_sync"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using user_id;
      end if;
    end;
  end if;
  return created;
end;
$$;
revoke execute on function "better_supabase"."sync_profile"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_profile"(uuid) to service_role;

-- Profiles for users that have none, after installing on an existing project.
create or replace function "better_supabase"."backfill_profiles"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from auth.users u where "better_supabase"."sync_profile"(u.id)
$$;
revoke execute on function "better_supabase"."backfill_profiles"() from public, anon, authenticated;
grant execute on function "better_supabase"."backfill_profiles"() to service_role;

drop function if exists "better_supabase"."my_profile"();
create or replace function "better_supabase"."my_profile"()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(p) from "better_supabase"."profiles" p where p."id" = (select auth.uid())
$$;
revoke execute on function "better_supabase"."my_profile"() from public, anon;
grant execute on function "better_supabase"."my_profile"() to authenticated, service_role;

create or replace function "better_supabase"."update_my_profile"(attrs jsonb)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  updated integer;
  v_caller uuid := (select auth.uid());
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_profile_update"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, v_caller;
    end if;
  end;
  update "better_supabase"."profiles" p
  set "full_name" = case when update_my_profile.attrs ? 'full_name' then update_my_profile.attrs ->> 'full_name' else p."full_name" end,
    "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "avatar_url" = case when update_my_profile.attrs ? 'avatar_url' then update_my_profile.attrs ->> 'avatar_url' else p."avatar_url" end,
    "avatar_path" = case when update_my_profile.attrs ? 'avatar_path' then update_my_profile.attrs ->> 'avatar_path' else p."avatar_path" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "onboarding" = case when update_my_profile.attrs ? 'onboarding' then update_my_profile.attrs -> 'onboarding' else p."onboarding" end,
    "updated_at" = now()
  where p."id" = v_caller;
  get diagnostics updated = row_count;
  if updated > 0 then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_update"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using v_caller;
      end if;
    end;
  end if;
  return updated > 0;
end;
$$;
revoke execute on function "better_supabase"."update_my_profile"(jsonb) from public, anon;
grant execute on function "better_supabase"."update_my_profile"(jsonb) to authenticated, service_role;

create or replace function better_supabase.replace_equivalent_triggers(
  target regclass,
  module_trigger text,
  pattern text,
  replace_trigger boolean
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  found record;
begin
  for found in
    select t.tgname as name, p.proname as fn
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = replace_equivalent_triggers.target
      and not t.tgisinternal
      and t.tgname <> replace_equivalent_triggers.module_trigger
      and p.proname ~* replace_equivalent_triggers.pattern
  loop
    if replace_trigger then
      execute format('drop trigger %I on %s', found.name, target);
    else
      raise warning '% already has trigger % (%), which does what % does. Pass replace_trigger => true to drop it.',
        target, found.name, found.fn, module_trigger;
    end if;
  end loop;
end;
$$;
revoke execute on function better_supabase.replace_equivalent_triggers(regclass, text, text, boolean) from public, anon, authenticated;

create or replace function "better_supabase"."on_auth_user_created"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A failure here would abort the sign-up. The user gets an account
  -- without a profile instead, and backfill_profiles() creates it later.
  begin
    perform "better_supabase"."sync_profile"(new.id);
  exception when others then
    raise warning 'No profile for user %: % (SQLSTATE %). Run backfill_profiles() once it is fixed.',
      new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
revoke execute on function "better_supabase"."on_auth_user_created"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_sync" on auth.users;
create trigger "bsb_profile_sync" after insert on auth.users
  for each row execute function "better_supabase"."on_auth_user_created"();

-- Keeps the profile's email equal to the confirmed address in auth.users.
create or replace function "better_supabase"."mirror_profile_email"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."profiles" set "email" = new.email where "id" = new.id and "email" is distinct from new.email;
  return new;
end;
$$;
revoke execute on function "better_supabase"."mirror_profile_email"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_email" on auth.users;
create trigger "bsb_profile_email" after update of email on auth.users
  for each row execute function "better_supabase"."mirror_profile_email"();

-- blocks.profiles.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."my_profile"();

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

create or replace function "api"."allocate_username"(base text, user_id uuid default null)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."allocate_username"($1, $2) $$;
revoke execute on function "api"."allocate_username"(text, uuid) from public, anon;
grant execute on function "api"."allocate_username"(text, uuid) to authenticated, service_role;

create or replace function "api"."sync_profile"(user_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."sync_profile"($1) $$;
revoke execute on function "api"."sync_profile"(uuid) from public, anon, authenticated;
grant execute on function "api"."sync_profile"(uuid) to service_role;

create or replace function "api"."backfill_profiles"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."backfill_profiles"() $$;
revoke execute on function "api"."backfill_profiles"() from public, anon, authenticated;
grant execute on function "api"."backfill_profiles"() to service_role;

create or replace function "api"."my_profile"()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."my_profile"() $$;
revoke execute on function "api"."my_profile"() from public, anon;
grant execute on function "api"."my_profile"() to authenticated, service_role;

create or replace function "api"."update_my_profile"(attrs jsonb)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_my_profile"($1) $$;
revoke execute on function "api"."update_my_profile"(jsonb) from public, anon;
grant execute on function "api"."update_my_profile"(jsonb) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_022_profiles.sql
-- better-supabase module: profiles
-- @bsb-block-data profiles
-- @bsb-hash sha256:45eb922a57d2c451d84537ff0eabe7454ea0b51feab4ae418357c20a37ce6116
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Warns about another trigger that also creates profiles (handle_new_user).
select better_supabase.replace_equivalent_triggers('auth.users', 'bsb_profile_sync', '(handle_new_user|create_profile|new_user_profile)', false);

insert into better_supabase.blocks (name, version, mode)
values ('profiles', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== adopt: schema supabase/schemas/900_better_supabase_022_profiles.sql
-- better-supabase module: profiles
-- @bsb-block profiles@2 adopt
-- @bsb-hash sha256:23e3412802d0e3c7b23fff2ed43f88b6d11ff33768c559e1ef194794efc5e1b9
-- A profile per user, created on sign-up from auth metadata with a unique username, an email mirror, column-level update grants and a guard on columns the service owns.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;


-- The API roles can't change the key or "email", "disabled_at", "active_organization_id", "active_team_id", "created_at". Security
-- definer functions (switch_organization, the email mirror) run as their
-- owner and pass.
create or replace function "better_supabase"."guard_profile"()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and (
    new."id" is distinct from old."id"
    or new."email" is distinct from old."email"
    or new."disabled_at" is distinct from old."disabled_at"
    or new."active_organization_id" is distinct from old."active_organization_id"
    or new."active_team_id" is distinct from old."active_team_id"
    or new."created_at" is distinct from old."created_at"
  ) then
    raise exception 'These profile columns are managed by the service' using errcode = '42501', hint = 'PROFILE_COLUMN_READONLY';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."guard_profile"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_guard" on "better_supabase"."profiles";
create trigger "bsb_profile_guard" before update on "better_supabase"."profiles"
  for each row execute function "better_supabase"."guard_profile"();

-- A free username from base: lowercased, stripped to [a-z0-9_], starting
-- with a letter, then suffixed with a number while it is reserved or
-- another profile has it.
create or replace function "better_supabase"."allocate_username"(base text, user_id uuid default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  stem text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]+', '', 'g'), 28);
  candidate text;
  n integer := 0;
begin
  if stem !~ '^[a-z]' then
    stem := left('u' || stem, 28);
  end if;
  if length(stem) < 3 then
    stem := 'user';
  end if;
  candidate := stem;
  while candidate = any(array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www']) or exists (
    select 1 from "better_supabase"."profiles" p
    where lower(p."username") = candidate and p."id" is distinct from user_id
  ) loop
    n := n + 1;
    candidate := stem || n::text;
  end loop;
  return candidate;
end;
$$;
revoke execute on function "better_supabase"."allocate_username"(text, uuid) from public, anon;
grant execute on function "better_supabase"."allocate_username"(text, uuid) to authenticated, service_role;

-- Creates the user's profile from auth.users when it has none: metadata
-- keys (blocks.profiles.options.metadata), the email and a username. The
-- after_profile_sync hook runs only for a profile it created.
create or replace function "better_supabase"."sync_profile"(user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  u auth.users;
  meta jsonb;
  created boolean := false;
  attempt integer := 0;
begin
  select * into u from auth.users where id = user_id;
  if not found then
    return false;
  end if;
  meta := coalesce(u.raw_user_meta_data, '{}');
  if not exists (select 1 from "better_supabase"."profiles" p where p."id" = user_id) then
    loop
      begin
        insert into "better_supabase"."profiles" ("id", "full_name", "first_name", "last_name", "avatar_url", "email", "username")
        values (user_id, coalesce(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), nullif(concat_ws(' ', nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), '')), '')), coalesce(nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1), '')), coalesce(nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), ''), nullif(btrim(substr(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), length(split_part(nullif(btrim(coalesce(meta ->> 'full_name', meta ->> 'name')), ''), ' ', 1)) + 1)), '')), nullif(btrim(coalesce(meta ->> 'avatar_url', meta ->> 'picture')), ''), u.email, "better_supabase"."allocate_username"(coalesce(nullif(btrim(coalesce(meta ->> 'user_name', meta ->> 'preferred_username', meta ->> 'username')), ''), split_part(u.email, '@', 1)), user_id));
        created := true;
        exit;
      exception when unique_violation then
        -- Another sign-up took the username between allocation and insert.
        attempt := attempt + 1;
        if attempt >= 3 or exists (select 1 from "better_supabase"."profiles" p where p."id" = user_id) then
          exit;
        end if;
      end;
    end loop;
  end if;
  if created then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_sync"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using user_id;
      end if;
    end;
  end if;
  return created;
end;
$$;
revoke execute on function "better_supabase"."sync_profile"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."sync_profile"(uuid) to service_role;

-- Profiles for users that have none, after installing on an existing project.
create or replace function "better_supabase"."backfill_profiles"()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from auth.users u where "better_supabase"."sync_profile"(u.id)
$$;
revoke execute on function "better_supabase"."backfill_profiles"() from public, anon, authenticated;
grant execute on function "better_supabase"."backfill_profiles"() to service_role;

drop function if exists "better_supabase"."my_profile"();
create or replace function "better_supabase"."my_profile"()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(p) from "better_supabase"."profiles" p where p."id" = (select auth.uid())
$$;
revoke execute on function "better_supabase"."my_profile"() from public, anon;
grant execute on function "better_supabase"."my_profile"() to authenticated, service_role;

create or replace function "better_supabase"."update_my_profile"(attrs jsonb)
returns boolean
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  updated integer;
  v_caller uuid := (select auth.uid());
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_profile_update"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, v_caller;
    end if;
  end;
  update "better_supabase"."profiles" p
  set "full_name" = case when update_my_profile.attrs ? 'full_name' then update_my_profile.attrs ->> 'full_name' else p."full_name" end,
    "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "avatar_url" = case when update_my_profile.attrs ? 'avatar_url' then update_my_profile.attrs ->> 'avatar_url' else p."avatar_url" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "onboarding" = case when update_my_profile.attrs ? 'onboarding' then update_my_profile.attrs -> 'onboarding' else p."onboarding" end,
    "updated_at" = now()
  where p."id" = v_caller;
  get diagnostics updated = row_count;
  if updated > 0 then
    declare
      v_hook regprocedure := to_regprocedure('"public"."after_profile_update"(uuid)');
    begin
      if v_hook is not null then
        execute format('select %s($1::uuid)', v_hook::oid::regproc)
          using v_caller;
      end if;
    end;
  end if;
  return updated > 0;
end;
$$;
revoke execute on function "better_supabase"."update_my_profile"(jsonb) from public, anon;
grant execute on function "better_supabase"."update_my_profile"(jsonb) to authenticated, service_role;

create or replace function better_supabase.replace_equivalent_triggers(
  target regclass,
  module_trigger text,
  pattern text,
  replace_trigger boolean
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  found record;
begin
  for found in
    select t.tgname as name, p.proname as fn
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = replace_equivalent_triggers.target
      and not t.tgisinternal
      and t.tgname <> replace_equivalent_triggers.module_trigger
      and p.proname ~* replace_equivalent_triggers.pattern
  loop
    if replace_trigger then
      execute format('drop trigger %I on %s', found.name, target);
    else
      raise warning '% already has trigger % (%), which does what % does. Pass replace_trigger => true to drop it.',
        target, found.name, found.fn, module_trigger;
    end if;
  end loop;
end;
$$;
revoke execute on function better_supabase.replace_equivalent_triggers(regclass, text, text, boolean) from public, anon, authenticated;

create or replace function "better_supabase"."on_auth_user_created"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- A failure here would abort the sign-up. The user gets an account
  -- without a profile instead, and backfill_profiles() creates it later.
  begin
    perform "better_supabase"."sync_profile"(new.id);
  exception when others then
    raise warning 'No profile for user %: % (SQLSTATE %). Run backfill_profiles() once it is fixed.',
      new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
revoke execute on function "better_supabase"."on_auth_user_created"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_sync" on auth.users;
create trigger "bsb_profile_sync" after insert on auth.users
  for each row execute function "better_supabase"."on_auth_user_created"();

-- Keeps the profile's email equal to the confirmed address in auth.users.
create or replace function "better_supabase"."mirror_profile_email"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "better_supabase"."profiles" set "email" = new.email where "id" = new.id and "email" is distinct from new.email;
  return new;
end;
$$;
revoke execute on function "better_supabase"."mirror_profile_email"() from public, anon, authenticated;
drop trigger if exists "bsb_profile_email" on auth.users;
create trigger "bsb_profile_email" after update of email on auth.users
  for each row execute function "better_supabase"."mirror_profile_email"();

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

-- ==== adopt: data supabase/better-supabase-data/900_better_supabase_022_profiles.sql
-- better-supabase module: profiles
-- @bsb-block-data profiles
-- @bsb-hash sha256:73d6da04f8bffba1be63b85185ef542457430923602b9980408b8e3e6c18175b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Warns about another trigger that also creates profiles (handle_new_user).
select better_supabase.replace_equivalent_triggers('auth.users', 'bsb_profile_sync', '(handle_new_user|create_profile|new_user_profile)', false);

insert into better_supabase.blocks (name, version, mode)
values ('profiles', 2, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
