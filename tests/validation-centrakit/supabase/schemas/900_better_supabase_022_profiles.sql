-- better-supabase module: profiles
-- @bsb-block profiles@3 managed
-- @bsb-hash sha256:376ab16133bb12443ba9628d9e65ace45fbae387e19d1b2397f09024e108a8d1
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
-- centrakit.profiles is the app's table, and it has every column this block needs.

create unique index if not exists profiles_username_idx on "centrakit"."profiles" (lower("username"));
do $$
begin
exception when check_violation then
  raise warning '% has usernames that break profiles_username_check, so only new ones are checked', '"centrakit"."profiles"';
end;
$$;
alter table "centrakit"."profiles" enable row level security;
drop policy if exists bsb_profiles_read on "centrakit"."profiles";
create policy bsb_profiles_read on "centrakit"."profiles"
  for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists bsb_profiles_update on "centrakit"."profiles";
create policy bsb_profiles_update on "centrakit"."profiles"
  for update to authenticated
  using (("user_id" = (select auth.uid())) and (select centrakit.authz_actor_may_write()))
  with check (("user_id" = (select auth.uid())) and (select centrakit.authz_actor_may_write()));
grant select on "centrakit"."profiles" to authenticated;
grant all on "centrakit"."profiles" to service_role;



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
    new."user_id" is distinct from old."user_id"
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
drop trigger if exists "bsb_profile_guard" on "centrakit"."profiles";
create trigger "bsb_profile_guard" before update on "centrakit"."profiles"
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
  stem text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]+', '', 'g'), 26);
  candidate text;
  n integer := 0;
begin
  if stem !~ '^[a-z]' then
    stem := left('u' || stem, 26);
  end if;
  if length(stem) < 3 then
    stem := 'user';
  end if;
  candidate := stem;
  while candidate = any(array['admin', 'administrator', 'api', 'app', 'auth', 'billing', 'help', 'login', 'logout', 'me', 'null', 'root', 'settings', 'signup', 'support', 'system', 'www']) or exists (
    select 1 from "centrakit"."profiles" p
    where lower(p."username") = candidate and p."user_id" is distinct from user_id
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
  if not exists (select 1 from "centrakit"."profiles" p where p."user_id" = user_id) then
    loop
      begin
        insert into "centrakit"."profiles" ("user_id", "first_name", "last_name", "email", "username")
        values (user_id, nullif(btrim(coalesce(meta ->> 'first_name')), ''), nullif(btrim(coalesce(meta ->> 'last_name')), ''), lower(u.email), "better_supabase"."allocate_username"(coalesce(nullif(btrim(coalesce(meta ->> 'user_name', meta ->> 'preferred_username', meta ->> 'username')), ''), split_part(u.email, '@', 1)), user_id));
        created := true;
        exit;
      exception when unique_violation then
        -- Another sign-up took the username between allocation and insert.
        attempt := attempt + 1;
        if attempt >= 3 or exists (select 1 from "centrakit"."profiles" p where p."user_id" = user_id) then
          exit;
        end if;
      end;
    end loop;
  end if;
  if created then
    declare
      v_hook regprocedure := to_regprocedure('"centrakit"."create_contact_profile"(uuid)');
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
  select to_jsonb(p) from "centrakit"."profiles" p where p."user_id" = (select auth.uid())
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
    v_hook regprocedure := to_regprocedure('"centrakit"."before_profile_update"(jsonb, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::jsonb, $2::uuid)', v_hook::oid::regproc)
        using attrs, v_caller;
    end if;
  end;
  update "centrakit"."profiles" p
  set "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "avatar_path" = case when update_my_profile.attrs ? 'avatar_path' then update_my_profile.attrs ->> 'avatar_path' else p."avatar_path" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "updated_at" = now()
  where p."user_id" = v_caller;
  get diagnostics updated = row_count;
  if updated > 0 then
    declare
      v_hook regprocedure := to_regprocedure('"centrakit"."after_profile_update"(uuid)');
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
drop trigger if exists "bsb_profile_sync" on auth.users;

-- Keeps the profile's email equal to the confirmed address in auth.users,
-- lowercased so lookups and unique indexes match regardless of case.
create or replace function "better_supabase"."mirror_profile_email"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "centrakit"."profiles" set "email" = lower(new.email) where "user_id" = new.id and "email" is distinct from lower(new.email);
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
