-- better-supabase module: profiles (0.5.1)
-- @bs-module profiles@2 managed
-- A profile per user, created on sign-up from auth metadata with a unique username, an email mirror, column-level update grants and a guard on columns the service owns.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

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
drop policy if exists bs_profiles_read on "better_supabase"."profiles";
create policy bs_profiles_read on "better_supabase"."profiles" for select to authenticated
  using ("id" = (select auth.uid()));
drop policy if exists bs_profiles_update on "better_supabase"."profiles";
create policy bs_profiles_update on "better_supabase"."profiles" for update to authenticated
  using ("id" = (select auth.uid()))
  with check ("id" = (select auth.uid()));
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
drop trigger if exists "bs_profile_guard" on "better_supabase"."profiles";
create trigger "bs_profile_guard" before update on "better_supabase"."profiles"
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
-- keys (modules.profiles.options.metadata), the email and a username. The
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
begin
  update "better_supabase"."profiles" p
  set "full_name" = case when update_my_profile.attrs ? 'full_name' then update_my_profile.attrs ->> 'full_name' else p."full_name" end,
    "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "avatar_url" = case when update_my_profile.attrs ? 'avatar_url' then update_my_profile.attrs ->> 'avatar_url' else p."avatar_url" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "onboarding" = case when update_my_profile.attrs ? 'onboarding' then update_my_profile.attrs -> 'onboarding' else p."onboarding" end,
    "updated_at" = now()
  where p."id" = (select auth.uid());
  get diagnostics updated = row_count;
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
drop trigger if exists "bs_profile_sync" on auth.users;
create trigger "bs_profile_sync" after insert on auth.users
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
drop trigger if exists "bs_profile_email" on auth.users;
create trigger "bs_profile_email" after update of email on auth.users
  for each row execute function "better_supabase"."mirror_profile_email"();

-- sql.modules.profiles.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
