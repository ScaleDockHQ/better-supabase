-- better-supabase module: profiles
-- @bsb-block profiles@3 managed
-- @bsb-hash sha256:99ed9cea151d796fc488bb108c515d7b712a72ca78af0d0abcaf78c005f25017
-- A profile per user, created on sign-up from auth metadata with a unique username, an email mirror, column-level update grants and a guard on columns the service owns.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- public.profiles is the app's table, and it has every column this block needs.

create unique index if not exists profiles_username_idx on "public"."profiles" (lower("username"));
alter table "public"."profiles" enable row level security;
create policy bsb_profiles_read on "public"."profiles"
  for select to authenticated
  using ("user_id" = (select auth.uid()));
create policy bsb_profiles_update on "public"."profiles"
  for update to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()))
  with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
grant select on "public"."profiles" to authenticated;
grant all on "public"."profiles" to service_role;



-- The API roles can't change the key or "email", "disabled_at", "active_organization_id", "active_team_id", "created_at". Security
-- definer functions (the email mirror among them) run as their owner and
-- pass.
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
create trigger "bsb_profile_guard" before update on "public"."profiles"
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
    select 1 from "public"."profiles" p
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
  if not exists (select 1 from "public"."profiles" p where p."user_id" = user_id) then
    loop
      begin
        insert into "public"."profiles" ("user_id", "first_name", "last_name", "email", "username")
        values (user_id, nullif(btrim(coalesce(meta ->> 'first_name', meta ->> 'given_name')), ''), nullif(btrim(coalesce(meta ->> 'last_name', meta ->> 'family_name')), ''), lower(u.email), "better_supabase"."allocate_username"(coalesce(nullif(btrim(coalesce(meta ->> 'user_name', meta ->> 'preferred_username', meta ->> 'username')), ''), split_part(u.email, '@', 1)), user_id));
        created := true;
        exit;
      exception when unique_violation then
        -- Another sign-up took the username between allocation and insert.
        attempt := attempt + 1;
        if attempt >= 3 or exists (select 1 from "public"."profiles" p where p."user_id" = user_id) then
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
create or replace function "better_supabase"."my_profile"()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(p) from "public"."profiles" p where p."user_id" = (select auth.uid())
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
  update "public"."profiles" p
  set "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "updated_at" = now()
  where p."user_id" = v_caller;
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

-- Keeps the profile's email equal to the confirmed address in auth.users,
-- lowercased so lookups and unique indexes match regardless of case.
create or replace function "better_supabase"."mirror_profile_email"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update "public"."profiles" set "email" = lower(new.email) where "user_id" = new.id and "email" is distinct from lower(new.email);
  return new;
end;
$$;
revoke execute on function "better_supabase"."mirror_profile_email"() from public, anon, authenticated;
