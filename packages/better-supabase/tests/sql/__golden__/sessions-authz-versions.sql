-- blocks['sessions'].options.authzVersions: one authorization version per
-- user. Attach better_supabase.bump_authz_version() to the tables a user's
-- access comes from; the access token hook reads better_supabase.authz_version().
create table if not exists better_supabase.user_authz_versions (
  user_id uuid primary key references auth.users on delete cascade,
  version bigint not null default 1,
  updated_at timestamptz not null default now()
);

alter table better_supabase.user_authz_versions enable row level security;

revoke all on better_supabase.user_authz_versions from public, anon, authenticated;
grant select on better_supabase.user_authz_versions to supabase_auth_admin;
grant all on better_supabase.user_authz_versions to service_role;

drop policy if exists bsb_authz_versions_auth_admin on better_supabase.user_authz_versions;
create policy bsb_authz_versions_auth_admin on better_supabase.user_authz_versions
  for select to supabase_auth_admin
  using (true);

-- The version the access token hook copies into authz_ver; 0 before the
-- first bump.
create or replace function better_supabase.authz_version(p_user uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select v.version from better_supabase.user_authz_versions v where v.user_id = p_user),
    0
  )
$$;

revoke execute on function better_supabase.authz_version(uuid) from public, anon, authenticated;
grant execute on function better_supabase.authz_version(uuid) to supabase_auth_admin, service_role;

-- Bumps the versions of many users at once, for changes no trigger sees.
create or replace function better_supabase.bump_authz_versions(p_users uuid[])
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into better_supabase.user_authz_versions as v (user_id)
  select distinct u from unnest(p_users) u where u is not null
  on conflict (user_id) do update
    set version = v.version + 1, updated_at = now()
$$;

revoke execute on function better_supabase.bump_authz_versions(uuid[]) from public, anon, authenticated;
grant execute on function better_supabase.bump_authz_versions(uuid[]) to service_role;

-- A row trigger: bumps the user in the row's user_id column, or in the column
-- named by the trigger's first argument, before and after an update.
create or replace function better_supabase.bump_authz_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  col text := coalesce(tg_argv[0], 'user_id');
begin
  perform better_supabase.bump_authz_versions(array[
    (to_jsonb(new) ->> col)::uuid,
    (to_jsonb(old) ->> col)::uuid
  ]);
  return null;
end;
$$;

revoke execute on function better_supabase.bump_authz_version() from public, anon, authenticated;

-- Sends { user_id, version } as the changed event on the server topic, which
-- no user may join, and on the user's own authz:<uid> topic.
create or replace function better_supabase.broadcast_authz_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('user_id', new.user_id, 'version', new.version), 'changed', 'better_supabase:authz', true);
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('user_id', new.user_id, 'version', new.version), 'changed', 'authz:' || new.user_id::text, true);
  end if;
  return null;
end;
$$;

revoke execute on function better_supabase.broadcast_authz_version() from public, anon, authenticated;

drop trigger if exists bsb_authz_versions_broadcast on better_supabase.user_authz_versions;
create trigger bsb_authz_versions_broadcast
  after insert or update on better_supabase.user_authz_versions
  for each row execute function better_supabase.broadcast_authz_version();

do $$
begin
  if to_regclass('realtime.messages') is not null then
    drop policy if exists bsb_authz_versions_receive on realtime.messages;
create policy bsb_authz_versions_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'broadcast' and (select realtime.topic()) = 'authz:' || (select auth.uid())::text);
  end if;
end;
$$;