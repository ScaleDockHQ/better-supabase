-- better-supabase add --adopt: the rows and settings of updated-at, memberships, permissions, organizations, profiles, seeds that no data migration holds yet.

set lock_timeout = '5s';

-- updated-at
insert into better_supabase.blocks (name, version, mode)
values ('updated-at', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- memberships
insert into better_supabase.blocks (name, version, mode)
values ('memberships', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- permissions
insert into better_supabase.blocks (name, version, mode)
values ('permissions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- organizations
insert into better_supabase.blocks (name, version, mode)
values ('organizations', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- profiles
select better_supabase.replace_equivalent_triggers('auth.users', 'bsb_profile_sync', '(handle_new_user|create_profile|new_user_profile)', false);

insert into better_supabase.blocks (name, version, mode)
values ('profiles', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- seeds
insert into better_supabase.blocks (name, version, mode)
values ('seeds', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
